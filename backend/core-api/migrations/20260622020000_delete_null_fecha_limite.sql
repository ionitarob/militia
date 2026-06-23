-- Remove licitaciones with no offer deadline — they can't be classified as
-- active or expired, skewing dashboard totals.
DELETE FROM licitacion WHERE fecha_limite_oferta IS NULL;
