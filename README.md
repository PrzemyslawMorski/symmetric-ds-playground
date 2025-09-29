SymmetricDS & Debezium Playground
=================================

Hands-on demos for replicating data from SQL Server to PostgreSQL using two approaches:

- Debezium (CDC via Kafka + JDBC Sink) — see `debezium/`
- SymmetricDS (bidirectional/ETL-style replication) — see `symmetric-ds/`

Prerequisites
-------------
-
- Docker Desktop (WSL2 backend recommended on Windows)
- PowerShell 7+ (examples use PowerShell)

Repository layout
-----------------
-
- `debezium/` — Debezium stack (ZooKeeper, Kafka, Connect, SQL Server, PostgreSQL) and connectors
- `symmetric-ds/` — SymmetricDS with SQL Server and PostgreSQL engines/config

Quick start: Debezium demo
--------------------------
-
```powershell
cd debezium
docker compose up -d

# Seed MSSQL (creates SuppliersDb and demo rows)
docker exec -it demo_mssql /opt/mssql-tools18/bin/sqlcmd -C -No -S localhost -U sa -P YourStrong!Passw0rd -i /docker-entrypoint-initdb.d/seed.sql

# Wait for Connect to be ready (repeat until 200 OK)
while (-not (Invoke-WebRequest -Uri http://localhost:8083/ -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue)) { Start-Sleep -Seconds 3 }

# Register source and sink connectors
Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri http://localhost:8083/connectors -InFile ./connectors/sqlserver-source.json
Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri http://localhost:8083/connectors -InFile ./connectors/postgres-jdbc-sink.json

# Insert a probe row on MSSQL and verify in Postgres
docker exec -it demo_mssql /opt/mssql-tools18/bin/sqlcmd -C -No -S localhost -U sa -P YourStrong!Passw0rd -Q "INSERT INTO SuppliersDb.dbo.Suppliers (Id, Name, Active) VALUES (NEWID(), 'Probe via Debezium', 1)"
docker exec -it demo_postgres psql -U postgres -d suppliers_replica -c 'SELECT * FROM "suppliers_suppliersdb_dbo_suppliers" ORDER BY 1 DESC LIMIT 5;'
```

Details and troubleshooting: see `debezium/README.md`.

Quick start: SymmetricDS demo
-----------------------------
-
```powershell
cd symmetric-ds
docker compose up -d

# Seed MSSQL once to create SuppliersDb and demo data
docker exec -it demo_mssql /opt/mssql-tools18/bin/sqlcmd -C -No -S localhost -U sa -P YourStrong!Passw0rd -i /docker-entrypoint-initdb.d/seed.sql

# Open registration for source node and trigger initial load
docker exec -it demo_symmetricds /opt/symmetric-ds/bin/symadmin --engine pg-000 open-registration -g mssql -i mssql-000
docker exec -it demo_symmetricds /opt/symmetric-ds/bin/symadmin --engine pg-000 reload-node -n mssql-000

# Test insert and verify replication
docker exec -it demo_mssql /opt/mssql-tools18/bin/sqlcmd -C -No -S localhost -U sa -P YourStrong!Passw0rd -Q "INSERT INTO SuppliersDb.dbo.Suppliers (Id, Name, Active) VALUES (NEWID(), 'Demo Supplier', 1)"
docker exec -it demo_postgres psql -U postgres -d suppliers_replica -c "SELECT * FROM dbo_suppliers ORDER BY updatedat DESC LIMIT 5;"
```

More commands and configuration notes: see `symmetric-ds/README.md`.

Resetting the demos
-------------------
From within each demo directory:

```powershell
docker compose down -v
```

Notes
-----
-
- Default ports: SQL Server `14333`, PostgreSQL `15433`, Debezium Connect `8083`, SymmetricDS `31415`, pgAdmin `5050` (if applicable).
- Credentials and connection strings are demo defaults; adjust for production use.

