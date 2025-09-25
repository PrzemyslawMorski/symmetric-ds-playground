SymmetricDS SQL Server → PostgreSQL Demo
=======================================

Prerequisites
-------------
- Docker Desktop (Windows WSL2 recommended)
- PowerShell 7+

Services
--------
- SQL Server 2022 (port 14333)
- PostgreSQL 16 (port 15433)
- SymmetricDS 3.14 (port 31415)

Quick start
-----------
```powershell
docker compose up -d

# IMPORTANT: Run MSSQL seed once to create SuppliersDb and demo data
docker exec -it demo_mssql /opt/mssql-tools18/bin/sqlcmd -C -No -S localhost -U sa -P YourStrong!Passw0rd -i /docker-entrypoint-initdb.d/seed.sql

# Open registration for source node and kick off initial load
docker exec -it demo_symmetricds /opt/symmetric-ds/bin/symadmin --engine pg-000 open-registration -g mssql -i mssql-000
docker exec -it demo_symmetricds /opt/symmetric-ds/bin/symadmin --engine pg-000 reload-node -n mssql-000

# Test insert on SQL Server
docker exec -it demo_mssql /opt/mssql-tools18/bin/sqlcmd -C -No -S localhost -U sa -P YourStrong!Passw0rd -Q "INSERT INTO SuppliersDb.dbo.Suppliers (Id, Name, Active) VALUES (NEWID(), 'Demo Supplier', 1)"

# Verify on Postgres
docker exec -it demo_postgres psql -U postgres -d suppliers_replica -c "SELECT * FROM dbo_suppliers ORDER BY updatedat DESC LIMIT 5;"
```

Configuration
-------------
- MSSQL seed: `mssql/seed.sql` (creates `SuppliersDb.dbo.Suppliers`).
- Postgres: tables are auto-created by SymmetricDS during initial load (defaults).
- SymmetricDS engines:
  - `symmetricds/engines/pg-000.properties` (root + Postgres target, trigger/transform definitions)
  - `symmetricds/engines/mssql-000.properties` (SQL Server source, auto-registration)

Common commands
---------------
```powershell
# Logs
docker logs -f demo_symmetricds

# Verify registration/status (image without list-nodes)
# 1) Check nodes in the DB
docker exec -it demo_postgres psql -U postgres -d suppliers_replica -c "SELECT node_id, node_group_id, sync_enabled FROM sym_node ORDER BY node_id;"

# 2) Check for error batches (optional)
docker exec -it demo_symmetricds /opt/symmetric-ds/bin/symadmin --engine pg-000 list-batches --status=ER

# Reset demo (destroys volumes!)
docker compose down -v
```

Notes
-----
- Adjust credentials and engine properties as needed for your environment.
- To replicate more tables, duplicate the `trigger.N` and `transform.table.N` blocks in `pg-000.properties` and create matching tables in Postgres.

Handling multiple PostgreSQL databases or schemas
-----------------------------------------------
- Separate databases (one engine per DB)
  - Create another DB:
    - `docker exec -it demo_postgres psql -U postgres -c "CREATE DATABASE other_suppliers;"`
  - Add a new engine (e.g., `symmetricds/engines/pg-001.properties`):
    - `engine.name=pg-001`
    - `db.url=jdbc:postgresql://postgres:5432/other_suppliers`
    - Unique `external.id` and `sync.url`
    - Define triggers/transforms as needed
  - Register and reload like `pg-000`.

- Multiple schemas in one database (simpler ops)
  - Keep `suppliers_replica`; route tables into schemas via transforms in `pg-000.properties`:
    - `transform.table.N.target.schema.name=<schema_name>`
    - Optionally `transform.table.N.target.table.name=<table_name>`
  - Pre-create schema if desired:
    - `docker exec -it demo_postgres psql -U postgres -d suppliers_replica -c "CREATE SCHEMA IF NOT EXISTS suppliers;"`

