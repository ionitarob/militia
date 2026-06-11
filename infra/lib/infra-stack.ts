import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as apigw from 'aws-cdk-lib/aws-apigateway';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as scheduler from 'aws-cdk-lib/aws-scheduler';
import * as wafv2 from 'aws-cdk-lib/aws-wafv2';
import { RustFunction } from 'cargo-lambda-cdk';
import * as path from 'path';

export class InfraStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // ── 1. VPC ────────────────────────────────────────────────────────────────
    // Public subnets: internet gateway is here (scraper_fetch Lambda also runs here).
    // Isolated subnets: core-api Lambda + RDS + scraper_write Lambda (need DB access).
    // No NAT gateways: scraper_fetch runs outside the VPC so it can reach the internet
    // freely; scraper_write is inside the VPC for RDS access.
    const vpc = new ec2.Vpc(this, 'LitiVpc', {
      maxAzs: 2,
      natGateways: 0,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'Isolated',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // ── 2. VPC Endpoints ──────────────────────────────────────────────────────

    // Secrets Manager interface endpoint: used by core-api + scraper_write Lambdas.
    vpc.addInterfaceEndpoint('SecretsManagerEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER,
      subnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
    });

    // SES interface endpoint: core-api sends OTP emails from inside the VPC.
    // Without this the isolated subnet has no route to SES's public HTTPS endpoint.
    // EMAIL covers the SES v2 API (ses.region.amazonaws.com); EMAIL_SMTP is for SMTP only.
    vpc.addInterfaceEndpoint('SesEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.EMAIL,
      subnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
    });

    // S3 gateway endpoint: FREE; allows scraper_write (isolated subnet) to read
    // the scrape payload from S3 without a NAT gateway.
    vpc.addGatewayEndpoint('S3Endpoint', {
      service: ec2.GatewayVpcEndpointAwsService.S3,
      subnets: [{ subnetType: ec2.SubnetType.PRIVATE_ISOLATED }],
    });

    // ── 3. Aurora Serverless v2 (PostgreSQL 16) ───────────────────────────────
    // Scales from 0.5 ACUs (idle) to 8 ACUs (peak) automatically.
    // Costs ~$0/month when unused; no provisioned capacity to pay for.
    const dbCluster = new rds.DatabaseCluster(this, 'LitiAuroraCluster', {
      engine: rds.DatabaseClusterEngine.auroraPostgres({
        version: rds.AuroraPostgresEngineVersion.VER_16_4,
      }),
      writer: rds.ClusterInstance.serverlessV2('writer'),
      serverlessV2MinCapacity: 0.5,
      serverlessV2MaxCapacity: 8,
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
      defaultDatabaseName: 'imliti',
      storageEncrypted: true,
      enableDataApi: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ── 4a. JWT signing secret ────────────────────────────────────────────────
    // 64-char random secret stored in Secrets Manager — never exposed as a
    // plain env var. The Lambda reads it via the SM API at cold-start.
    const jwtSecret = new secretsmanager.Secret(this, 'JwtSecret', {
      secretName: 'LitiJwtSecret',
      description: 'JWT HS256 signing secret for IMLiti API',
      generateSecretString: {
        passwordLength: 64,
        excludePunctuation: true,
      },
    });

    // ── 4. Core-API Rust Lambda (in VPC) ──────────────────────────────────────
    const coreApiLambda = new RustFunction(this, 'CoreApiLambda', {
      manifestPath: path.join(__dirname, '../../backend/core-api/Cargo.toml'),
      // bundling.assetHash forces CDK to re-hash the full source dir (including migrations/)
      // so adding a new .sql file triggers a Lambda rebuild and redeploy.
      bundling: {
        assetHashType: cdk.AssetHashType.SOURCE,
      },
      architecture: cdk.aws_lambda.Architecture.ARM_64,
      memorySize: 256,
      timeout: cdk.Duration.seconds(30),
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
      environment: {
        DB_SECRET_ARN:  dbCluster.secret?.secretArn ?? '',
        JWT_SECRET_ARN: jwtSecret.secretArn,
        SMTP_USER:      'reporting.imes.config@gmail.com',
        SMTP_PASS:      'wcysrqrktblbehln',
        RUST_LOG:       'info',
        S3_BUCKET:      `imliti-scrapes-${this.account}`,
      },
    });

    dbCluster.connections.allowFrom(coreApiLambda, ec2.Port.tcp(5432));
    dbCluster.secret?.grantRead(coreApiLambda);
    jwtSecret.grantRead(coreApiLambda);

    // Allow core-api to send OTP emails via SES v2.
    // The identity (from-address domain) must be verified in SES before deploy.
    // Grant send permission scoped to the verified Gmail sender identity.
    // Verify it once with: aws sesv2 create-email-identity --email-address reporting.imes.config@gmail.com
    coreApiLambda.addToRolePolicy(new iam.PolicyStatement({
      actions: ['ses:SendEmail', 'ses:SendRawEmail'],
      resources: [
        `arn:aws:ses:${this.region}:${this.account}:identity/reporting.imes.config@gmail.com`,
      ],
    }));

    // ── 5. API Gateway ────────────────────────────────────────────────────────
    const api = new apigw.LambdaRestApi(this, 'LitiApiGateway', {
      handler: coreApiLambda,
      deployOptions: {
        // Stage-level throttle: 20 req/s steady, 50 burst.
        // Protects the Lambda and the DB from traffic spikes / brute-force.
        throttlingRateLimit:  20,
        throttlingBurstLimit: 50,
      },
    });

    // ── 5a. WAF — rate limiting + AWS Managed Rules ───────────────────────────
    // ~$7/month: $5 WebACL + $1 AWSCommonRuleSet + $0.60/M requests.
    const webAcl = new wafv2.CfnWebACL(this, 'ApiWaf', {
      scope: 'REGIONAL',
      defaultAction: { allow: {} },
      visibilityConfig: {
        cloudWatchMetricsEnabled: true,
        metricName: 'LitiApiWaf',
        sampledRequestsEnabled: true,
      },
      rules: [
        {
          // Block any single IP that sends > 200 requests in 5 minutes.
          // Stops brute-force on /auth/login and crawlers.
          name: 'IPRateLimitRule',
          priority: 1,
          action: { block: {} },
          statement: {
            rateBasedStatement: {
              limit: 200,
              aggregateKeyType: 'IP',
            },
          },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: 'LitiIPRateLimit',
            sampledRequestsEnabled: true,
          },
        },
        {
          // AWS-managed ruleset: SQLi, XSS, known bad inputs, size restrictions.
          name: 'AWSManagedRulesCommonRuleSet',
          priority: 2,
          overrideAction: { none: {} },
          statement: {
            managedRuleGroupStatement: {
              vendorName: 'AWS',
              name: 'AWSManagedRulesCommonRuleSet',
            },
          },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: 'LitiCommonRules',
            sampledRequestsEnabled: true,
          },
        },
        {
          // Block known bad IPs (Tor exit nodes, scanners, botnets).
          name: 'AWSManagedRulesAmazonIpReputationList',
          priority: 3,
          overrideAction: { none: {} },
          statement: {
            managedRuleGroupStatement: {
              vendorName: 'AWS',
              name: 'AWSManagedRulesAmazonIpReputationList',
            },
          },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: 'LitiIpReputation',
            sampledRequestsEnabled: true,
          },
        },
      ],
    });

    // Associate WAF with the API Gateway deployment stage
    new wafv2.CfnWebACLAssociation(this, 'ApiWafAssociation', {
      resourceArn: `arn:aws:apigateway:${this.region}::/restapis/${api.restApiId}/stages/${api.deploymentStage.stageName}`,
      webAclArn: webAcl.attrArn,
    });

    // ── 6. Staging S3 bucket ──────────────────────────────────────────────────
    // scraper_fetch writes JSON here; scraper_write is triggered by ObjectCreated.
    const scrapeBucket = new s3.Bucket(this, 'ScrapeBucket', {
      bucketName: `imliti-scrapes-${this.account}`,
      // Block ACLs but allow public bucket policy for the app/ download prefix.
      blockPublicAccess: new s3.BlockPublicAccess({
        blockPublicAcls:       true,
        ignorePublicAcls:      true,
        blockPublicPolicy:     false,
        restrictPublicBuckets: false,
      }),
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          // Only auto-delete scrape JSON files; documents/ prefix is kept indefinitely.
          prefix: 'scrapes/',
          expiration: cdk.Duration.days(30),
        },
      ],
    });

    // ── 7. Portal credentials secret ─────────────────────────────────────────
    // Store manually via: aws secretsmanager put-secret-value \
    //   --secret-id LitiPortalCredentials \
    //   --secret-string '{"username":"Cristina.Giraldo@ingrammicro.com","password":"ADJU2025"}'
    const portalSecret = new secretsmanager.Secret(this, 'PortalCredentials', {
      secretName: 'LitiPortalCredentials',
      description: 'Credentials for the adjudicacionestic.com portal scraper',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'Cristina.Giraldo@ingrammicro.com' }),
        generateStringKey: 'password',  // placeholder — overwrite via CLI after first deploy
      },
    });

    // ── 8. scraper_fetch Lambda (NO VPC — needs internet access) ─────────────
    // Runs outside the VPC so it can reach adjudicacionestic.com.
    // Writes scraped JSON to S3; scraper_write Lambda takes it from there.
    const scraperFetchLambda = new lambda.Function(this, 'ScraperFetchLambda', {
      runtime: lambda.Runtime.PYTHON_3_12,
      architecture: lambda.Architecture.ARM_64,
      handler: 'handler.lambda_handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../../backend/scraper_fetch'), {
        bundling: {
          image: lambda.Runtime.PYTHON_3_12.bundlingImage,
          platform: 'linux/arm64',
          command: [
            'bash', '-c',
            'pip install -r requirements.txt -t /asset-output && cp -au . /asset-output',
          ],
        },
      }),
      memorySize: 512,
      timeout: cdk.Duration.minutes(15),
      reservedConcurrentExecutions: 1,
      environment: {
        PORTAL_SECRET_ARN: portalSecret.secretArn,
        S3_BUCKET: scrapeBucket.bucketName,
        DB_CLUSTER_ARN: dbCluster.clusterArn,
        DB_SECRET_ARN: dbCluster.secret?.secretArn ?? '',
      },
    });

    portalSecret.grantRead(scraperFetchLambda);
    scrapeBucket.grantReadWrite(scraperFetchLambda);
    // refresh_open mode: query open licitaciones via Aurora Data API (no VPC needed)
    dbCluster.secret?.grantRead(scraperFetchLambda);
    scraperFetchLambda.addToRolePolicy(new iam.PolicyStatement({
      actions: ['rds-data:ExecuteStatement'],
      resources: [dbCluster.clusterArn],
    }));
    // refresh_open self-re-invokes when batch is too large for one execution.
    // Using account-scoped wildcard to avoid a CDK circular dependency
    // (functionArn → Lambda → role → policy → functionArn).
    scraperFetchLambda.addToRolePolicy(new iam.PolicyStatement({
      actions: ['lambda:InvokeFunction'],
      resources: [`arn:aws:lambda:${this.region}:${this.account}:function:*`],
    }));

    // ── 9. scraper_write Lambda (in VPC — needs RDS access) ──────────────────
    // Triggered by S3 ObjectCreated events from scraper_fetch.
    // Reads JSON from S3 (via gateway endpoint) and upserts into RDS.
    const scraperWriteLambda = new lambda.Function(this, 'ScraperWriteLambda', {
      runtime: lambda.Runtime.PYTHON_3_12,
      architecture: lambda.Architecture.ARM_64,
      handler: 'handler.lambda_handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../../backend/scraper_write'), {
        bundling: {
          image: lambda.Runtime.PYTHON_3_12.bundlingImage,
          platform: 'linux/arm64',
          command: [
            'bash', '-c',
            'pip install -r requirements.txt -t /asset-output && cp -au . /asset-output',
          ],
        },
      }),
      memorySize: 256,
      timeout: cdk.Duration.minutes(10),
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
      environment: {
        DB_SECRET_ARN: dbCluster.secret?.secretArn ?? '',
      },
    });

    dbCluster.connections.allowFrom(scraperWriteLambda, ec2.Port.tcp(5432));
    dbCluster.secret?.grantRead(scraperWriteLambda);
    scrapeBucket.grantRead(scraperWriteLambda);
    scrapeBucket.grantRead(coreApiLambda, 'documents/*');
    scrapeBucket.grantReadWrite(coreApiLambda, 'cotizaciones/*');
    scrapeBucket.grantDelete(coreApiLambda, 'cotizaciones/*');

    // Public read for app/ prefix — allows the desktop client to download
    // the update manifest and release zips without authentication.
    scrapeBucket.addToResourcePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      principals: [new iam.StarPrincipal()],
      actions: ['s3:GetObject'],
      resources: [scrapeBucket.arnForObjects('app/*')],
    }));

    // Wire S3 → scraper_write trigger
    scrapeBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(scraperWriteLambda),
      { prefix: 'scrapes/' },
    );

    // ── 10. EventBridge Scheduler ─────────────────────────────────────────────
    // Fires at 20:00 Spain time (CET = UTC+1, CEST = UTC+2 in summer).
    // Using Europe/Madrid timezone so AWS handles the DST shift automatically.
    const schedulerRole = new iam.Role(this, 'SchedulerRole', {
      assumedBy: new iam.ServicePrincipal('scheduler.amazonaws.com'),
    });

    scraperFetchLambda.grantInvoke(schedulerRole);

    new scheduler.CfnSchedule(this, 'DailyScrapeSchedule', {
      name: 'imliti-daily-scrape',
      description: 'Fetch new licitaciones + adjudicaciones daily at 20:00 Spain time',
      scheduleExpression: 'cron(0 20 * * ? *)',
      scheduleExpressionTimezone: 'Europe/Madrid',
      flexibleTimeWindow: { mode: 'OFF' },
      target: {
        arn: scraperFetchLambda.functionArn,
        roleArn: schedulerRole.roleArn,
        input: JSON.stringify({ source: 'scheduler', mode: 'daily' }),
        retryPolicy: { maximumRetryAttempts: 0 },
      },
    });

    // Refresh still-open licitaciones every 3 days so we track deadline extensions,
    // cancellations, or any other field changes after the publication window closes.
    new scheduler.CfnSchedule(this, 'RefreshOpenSchedule', {
      name: 'imliti-refresh-open',
      description: 'Re-fetch detail pages for open licitaciones every 3 days at 08:00 Spain time',
      scheduleExpression: 'rate(3 days)',
      scheduleExpressionTimezone: 'Europe/Madrid',
      flexibleTimeWindow: { mode: 'OFF' },
      target: {
        arn: scraperFetchLambda.functionArn,
        roleArn: schedulerRole.roleArn,
        input: JSON.stringify({ source: 'scheduler', mode: 'refresh_open' }),
        retryPolicy: { maximumRetryAttempts: 0 },
      },
    });

    // ── 11. Outputs ───────────────────────────────────────────────────────────
    new cdk.CfnOutput(this, 'ApiUrl', {
      value: api.url,
      description: 'API Gateway URL',
    });

    new cdk.CfnOutput(this, 'ScrapeBucketName', {
      value: scrapeBucket.bucketName,
      description: 'S3 bucket for scraped data',
    });

    new cdk.CfnOutput(this, 'PortalSecretArn', {
      value: portalSecret.secretArn,
      description: 'ARN of the portal credentials secret — update after deploy',
    });

    new cdk.CfnOutput(this, 'JwtSecretArn', {
      value: jwtSecret.secretArn,
      description: 'ARN of the JWT signing secret (auto-generated, stored in Secrets Manager)',
    });
  }
}
