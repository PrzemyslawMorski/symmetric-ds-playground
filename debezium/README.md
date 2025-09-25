Debezium-based SQL Server → PostgreSQL Demo
===========================================

Reference: Debezium 3.2 Tutorial [https://debezium.io/documentation/reference/3.2/tutorial.html]

Stack
-----
- ZooKeeper, Kafka, Debezium Connect
- SQL Server 2022 (seeded SuppliersDb)
- PostgreSQL 16 (autocreate tables via JDBC sink)

Quick start
-----------
```powershell
docker compose up -d

# Seed MSSQL (creates SuppliersDb and demo rows)
docker exec -it demo_mssql /opt/mssql-tools18/bin/sqlcmd -C -No -S localhost -U sa -P YourStrong!Passw0rd -i /docker-entrypoint-initdb.d/seed.sql

# Wait for Connect to be ready
Invoke-RestMethod http://localhost:8083/ -TimeoutSec 5 -ErrorAction SilentlyContinue | Out-Null

# Register SQL Server source connector
Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri http://localhost:8083/connectors -InFile ./connectors/sqlserver-source.json

# Register JDBC sink to Postgres
Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri http://localhost:8083/connectors -InFile ./connectors/postgres-jdbc-sink.json

# Insert a probe row on MSSQL
docker exec -it demo_mssql /opt/mssql-tools18/bin/sqlcmd -C -No -S localhost -U sa -P YourStrong!Passw0rd -Q "INSERT INTO SuppliersDb.dbo.Suppliers (Id, Name, Active) VALUES (NEWID(), 'Probe via Debezium', 1)"

# Verify on Postgres (table auto-created by sink)
docker exec -it demo_postgres psql -U postgres -d suppliers_replica -c "\dt"
docker exec -it demo_postgres psql -U postgres -d suppliers_replica -c "SELECT * FROM \"suppliers.dbo.Suppliers\" LIMIT 5;"  # topic-derived naming
```

Notes
-----
- If Connect returns 409, the connector already exists; use PUT to update.
- JDBC Sink depends on the Confluent JDBC connector bundled in Debezium Connect 3.2 images.
- Topics are prefixed with `suppliers` as configured; adjust sink `topics.regex` accordingly.

