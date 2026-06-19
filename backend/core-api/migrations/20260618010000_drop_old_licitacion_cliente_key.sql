-- Drop the correct old unique constraint for client cotizaciones
ALTER TABLE licitacion_cotizacion
    DROP CONSTRAINT IF EXISTS licitacion_cotizacion_licitacion_cliente_key;
