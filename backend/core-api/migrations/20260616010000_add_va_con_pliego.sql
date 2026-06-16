-- Add va_con_pliego column to client cotizacion table
ALTER TABLE licitacion_cotizacion
    ADD COLUMN IF NOT EXISTS va_con_pliego BOOLEAN;
