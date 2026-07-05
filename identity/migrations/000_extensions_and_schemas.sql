-- Nexa Docker: Extensions and schemas (runs first on new database)
-- Creates extensions and schemas required by Nexa Pay, Nexa Go, Nexa Go Delivery

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE SCHEMA IF NOT EXISTS go;
CREATE SCHEMA IF NOT EXISTS go_delivery;
CREATE SCHEMA IF NOT EXISTS admin;
