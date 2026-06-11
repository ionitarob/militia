INSERT INTO app_user (email, password_hash, role, nombre)
VALUES (
    'alejandro.maglan@ingrammicro.com',
    '$2b$12$SYGWO1hfnPRr8pUqXrFrMuxxwBxzRaEnhxmAtPy2M8NsMC5JE6dl6',
    'admin',
    'Alejandro Maglan'
)
ON CONFLICT (email) DO NOTHING;
