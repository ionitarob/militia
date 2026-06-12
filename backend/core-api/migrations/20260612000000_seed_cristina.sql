INSERT INTO app_user (email, password_hash, role, nombre)
VALUES (
    'cristina.jimenez@ingrammicro.com',
    '$2b$12$xqTgK1Yv4P1fPggUvG05duo/ueZ2scIGg2QvKRsYauMAonRP7ommm',
    'ventas',
    'Cristina Jiménez'
)
ON CONFLICT (email) DO NOTHING;
