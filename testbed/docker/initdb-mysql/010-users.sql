-- Monitoring + replication users, created declaratively on first init.
-- mysql_native_password so DBD::mysql 4.x can authenticate over TCP.
-- These statements are binlogged, so the GTID-auto-positioned replica
-- inherits both users without its own init step.
CREATE USER IF NOT EXISTS 'mon'@'%' IDENTIFIED WITH mysql_native_password BY 'monpass';
GRANT ALL PRIVILEGES ON *.* TO 'mon'@'%';
CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'replpass';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;
