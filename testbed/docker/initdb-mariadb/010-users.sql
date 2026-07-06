-- Monitoring user for the MariaDB services, created on first init.
CREATE USER IF NOT EXISTS 'mon'@'%' IDENTIFIED BY 'monpass';
GRANT ALL PRIVILEGES ON *.* TO 'mon'@'%';
FLUSH PRIVILEGES;
