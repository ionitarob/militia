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

    // Bedrock Runtime interface endpoint: core-api calls Claude from inside the isolated subnet.
    // privateDnsEnabled ensures bedrock-runtime.region.amazonaws.com resolves to the
    // endpoint's private IP rather than the public IP (unreachable from isolated subnets).
    vpc.addInterfaceEndpoint('BedrockRuntimeEndpoint', {
      service: new ec2.InterfaceVpcEndpointService(`com.amazonaws.${this.region}.bedrock-runtime`, 443),
      privateDnsEnabled: true,
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

    // Lambda interface endpoint: allows SummarizeLambda (isolated subnet) to invoke
    // ScraperFetchLambda synchronously for on-demand document fetching.
    vpc.addInterfaceEndpoint('LambdaEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.LAMBDA,
      subnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
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
    // Note: timeout raised to 90s so chat-with-documents calls (PDF download +
    // Bedrock inference) have headroom. The 29s API Gateway limit is irrelevant
    // for /chat because that endpoint is now served exclusively via Function URL.
    const coreApiLambda = new RustFunction(this, 'CoreApiLambda', {
      manifestPath: path.join(__dirname, '../../backend/core-api/Cargo.toml'),
      binaryName: 'bootstrap',
      bundling: {
        assetHashType: cdk.AssetHashType.SOURCE,
      },
      architecture: cdk.aws_lambda.Architecture.ARM_64,
      memorySize: 256,
      timeout: cdk.Duration.seconds(90),
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

    // Allow core-api to call Bedrock (Claude) for the AI assistant chat feature.
    coreApiLambda.addToRolePolicy(new iam.PolicyStatement({
      actions: ['bedrock:InvokeModel', 'bedrock:InvokeModelWithResponseStream'],
      resources: ['*'],
    }));

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

    // ── 4b. Chat-Stream Lambda (streaming SSE, bypasses API GW 29s limit) ────
    // Separate binary compiled from the same Cargo workspace (binaryName: chat-stream).
    // Served via Lambda Function URL in RESPONSE_STREAM mode — no API Gateway.
    const chatStreamLambda = new RustFunction(this, 'ChatStreamLambda', {
      manifestPath: path.join(__dirname, '../../backend/core-api/Cargo.toml'),
      binaryName: 'chat-stream',
      bundling: {
        assetHashType: cdk.AssetHashType.SOURCE,
      },
      architecture: cdk.aws_lambda.Architecture.ARM_64,
      memorySize: 512,
      timeout: cdk.Duration.seconds(120),
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
      environment: {
        DB_SECRET_ARN:  dbCluster.secret?.secretArn ?? '',
        JWT_SECRET_ARN: jwtSecret.secretArn,
        RUST_LOG:       'info',
        S3_BUCKET:      `imliti-scrapes-${this.account}`,
      },
    });

    dbCluster.connections.allowFrom(chatStreamLambda, ec2.Port.tcp(5432));
    dbCluster.secret?.grantRead(chatStreamLambda);
    jwtSecret.grantRead(chatStreamLambda);

    chatStreamLambda.addToRolePolicy(new iam.PolicyStatement({
      actions: ['bedrock:InvokeModel', 'bedrock:InvokeModelWithResponseStream'],
      resources: ['*'],
    }));

    // ── 4c. Summarize Lambda (Haiku, streaming SSE, no session overhead) ────────
    // Purpose-built for Resumen Liti: parallel S3 doc downloads + Haiku inference.
    // Uses the same RESPONSE_STREAM Function URL pattern as chat-stream.
    const summarizeLambda = new RustFunction(this, 'SummarizeLambda', {
      manifestPath: path.join(__dirname, '../../backend/core-api/Cargo.toml'),
      binaryName: 'summarize',
      bundling: {
        assetHashType: cdk.AssetHashType.SOURCE,
      },
      architecture: cdk.aws_lambda.Architecture.ARM_64,
      memorySize: 512,
      timeout: cdk.Duration.seconds(120),
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
      environment: {
        DB_SECRET_ARN:  dbCluster.secret?.secretArn ?? '',
        JWT_SECRET_ARN: jwtSecret.secretArn,
        RUST_LOG:       'info',
        S3_BUCKET:      `imliti-scrapes-${this.account}`,
        // Set after scraperFetchLambda is defined below — injected via addEnvironment
      },
    });

    dbCluster.connections.allowFrom(summarizeLambda, ec2.Port.tcp(5432));
    dbCluster.secret?.grantRead(summarizeLambda);
    jwtSecret.grantRead(summarizeLambda);

    summarizeLambda.addToRolePolicy(new iam.PolicyStatement({
      actions: ['bedrock:InvokeModel', 'bedrock:InvokeModelWithResponseStream'],
      resources: ['*'],
    }));

    // Cross-region inference profiles require Marketplace subscription checks.
    summarizeLambda.addToRolePolicy(new iam.PolicyStatement({
      actions: ['aws-marketplace:ViewSubscriptions', 'aws-marketplace:Subscribe'],
      resources: ['*'],
    }));

    const summarizeUrl = summarizeLambda.addFunctionUrl({
      authType: lambda.FunctionUrlAuthType.NONE,
      invokeMode: lambda.InvokeMode.RESPONSE_STREAM,
      cors: {
        allowedOrigins: ['*'],
        allowedHeaders: ['Authorization', 'Content-Type'],
        allowedMethods: [lambda.HttpMethod.POST],
        allowCredentials: false,
        maxAge: cdk.Duration.hours(24),
      },
    });

    const chatStreamUrl = chatStreamLambda.addFunctionUrl({
      authType: lambda.FunctionUrlAuthType.NONE,
      invokeMode: lambda.InvokeMode.RESPONSE_STREAM,
      cors: {
        allowedOrigins: ['*'],
        allowedHeaders: ['Authorization', 'Content-Type'],
        allowedMethods: [lambda.HttpMethod.POST],
        allowCredentials: false,
        maxAge: cdk.Duration.hours(24),
      },
    });

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

    // SummarizeLambda and ChatStreamLambda invoke ScraperFetchLambda on-demand:
    // (1) when no docs in DB yet, (2) to follow PDF hyperlinks for the PPT.
    // Both are in the isolated subnet — the Lambda VPC endpoint above provides access.
    summarizeLambda.addEnvironment('SCRAPER_FETCH_ARN', scraperFetchLambda.functionArn);
    scraperFetchLambda.grantInvoke(summarizeLambda);
    chatStreamLambda.addEnvironment('SCRAPER_FETCH_ARN', scraperFetchLambda.functionArn);
    scraperFetchLambda.grantInvoke(chatStreamLambda);

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
    scrapeBucket.grantRead(chatStreamLambda, 'documents/*');
    scrapeBucket.grantRead(chatStreamLambda, 'cotizaciones/*');
    scrapeBucket.grantRead(summarizeLambda, 'documents/*');
    scrapeBucket.grantRead(summarizeLambda, 'cotizaciones/*');

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

    // ── 10. TendersTool ingest Lambda (NO VPC — needs internet access) ──────────
    // Calls TendersTool REST API and writes JSON to S3 (scrapes/ prefix).
    // scraper_write picks it up via the existing S3 ObjectCreated trigger.
    // Credentials stored in a separate secret so portal + API creds stay isolated.
    // Secret value is managed outside CDK — set once manually:
    //   aws secretsmanager put-secret-value --secret-id LitiTendersToolCredentials \
    //     --secret-string '{"email":"sergi.domingo@ingrammmicro.com","password":"..."}'
    // CDK only holds a reference so it can wire up IAM — never touches the value.
    const tenderToolSecret = secretsmanager.Secret.fromSecretNameV2(
      this, 'TendersToolCredentials', 'LitiTendersToolCredentials'
    );

    const ingestTendersToolLambda = new lambda.Function(this, 'IngestTendersToolLambda', {
      runtime: lambda.Runtime.PYTHON_3_12,
      architecture: lambda.Architecture.ARM_64,
      handler: 'handler.lambda_handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../../backend/ingest_tenderstool'), {
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
      environment: {
        TENDERSTOOL_SECRET_ARN: tenderToolSecret.secretArn,
        S3_BUCKET: scrapeBucket.bucketName,
      },
    });

    tenderToolSecret.grantRead(ingestTendersToolLambda);
    scrapeBucket.grantReadWrite(ingestTendersToolLambda);

    // ── 10. EventBridge Scheduler ─────────────────────────────────────────────
    // Fires at 20:00 Spain time (CET = UTC+1, CEST = UTC+2 in summer).
    // Using Europe/Madrid timezone so AWS handles the DST shift automatically.
    const schedulerRole = new iam.Role(this, 'SchedulerRole', {
      assumedBy: new iam.ServicePrincipal('scheduler.amazonaws.com'),
    });

    scraperFetchLambda.grantInvoke(schedulerRole);
    ingestTendersToolLambda.grantInvoke(schedulerRole);

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

    // TendersTool ingest runs at 06:00 Spain time — well before the portal scraper
    // at 20:00 — so both sources land in the DB on the same day.
    new scheduler.CfnSchedule(this, 'DailyTendersToolSchedule', {
      name: 'imliti-daily-tenderstool',
      description: 'Ingest new licitaciones from TendersTool API daily at 06:00 Spain time',
      scheduleExpression: 'cron(0 6 * * ? *)',
      scheduleExpressionTimezone: 'Europe/Madrid',
      flexibleTimeWindow: { mode: 'OFF' },
      target: {
        arn: ingestTendersToolLambda.functionArn,
        roleArn: schedulerRole.roleArn,
        input: JSON.stringify({ source: 'scheduler', days_back: 2 }),
        retryPolicy: { maximumRetryAttempts: 1 },
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

    new cdk.CfnOutput(this, 'TendersToolSecretArn', {
      value: tenderToolSecret.secretArn,
      description: 'ARN of the TendersTool API credentials secret — set real password after deploy',
    });

    new cdk.CfnOutput(this, 'ChatStreamUrl', {
      value: chatStreamUrl.url,
      description: 'Lambda Function URL for streaming chat (bypasses API GW 29s timeout)',
    });

    new cdk.CfnOutput(this, 'SummarizeUrl', {
      value: summarizeUrl.url,
      description: 'Lambda Function URL for Resumen Liti (Haiku, fast)',
    });
  }
}
