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
cd debezium
docker compose up -d

# Seed MSSQL (creates SuppliersDb and demo rows)
docker exec -it demo_mssql /opt/mssql-tools18/bin/sqlcmd -C -No -S localhost -U sa -P YourStrong!Passw0rd -i /docker-entrypoint-initdb.d/seed.sql

# Wait for Connect to be ready (repeat until 200 OK)
while (-not (Invoke-WebRequest -Uri http://localhost:8083/ -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue)) { Start-Sleep -Seconds 3 }

# Register SQL Server source connector
Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri http://localhost:8083/connectors -InFile ./connectors/sqlserver-source.json

# Register JDBC sink to Postgres
Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri http://localhost:8083/connectors -InFile ./connectors/postgres-jdbc-sink.json

# Insert a probe row on MSSQL
docker exec -it demo_mssql /opt/mssql-tools18/bin/sqlcmd -C -No -S localhost -U sa -P YourStrong!Passw0rd -Q "INSERT INTO SuppliersDb.dbo.Suppliers (Id, Name, Active) VALUES (NEWID(), 'Probe via Debezium', 1)"

# Verify on Postgres (table auto-created by sink)
docker exec -it demo_postgres psql -U postgres -d suppliers_replica -c "\dt"
docker exec -it demo_postgres psql -U postgres -d suppliers_replica -c 'SELECT * FROM "suppliers_suppliersdb_dbo_suppliers";'  # topic-derived naming
```

Inspect Kafka events
--------------------
```powershell
# List topics
docker exec -it dbz_kafka bash bin/kafka-topics.sh --list --bootstrap-server kafka:9092

# Describe the Debezium topic
docker exec -it dbz_kafka bash bin/kafka-topics.sh --describe --bootstrap-server kafka:9092 --topic suppliers.SuppliersDb.dbo.Suppliers

# Consume events from the beginning (print keys)
docker exec -it dbz_kafka bash bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic suppliers.SuppliersDb.dbo.Suppliers --from-beginning --property print.key=true --property key.separator=" | "
```

If registration fails: force-enable CDC for the table
-----------------------------------------------------
Sometimes table-level CDC may not be enabled yet. Run this once to create the capture instance and CDC jobs, then retry registration:
```powershell
docker exec -it demo_mssql /opt/mssql-tools18/bin/sqlcmd -C -No -S localhost -U sa -P YourStrong!Passw0rd -Q "USE SuppliersDb; IF EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id WHERE t.name='Suppliers' AND s.name='dbo') BEGIN IF NOT EXISTS (SELECT 1 FROM cdc.change_tables WHERE source_object_id = OBJECT_ID('dbo.Suppliers')) EXEC sys.sp_cdc_enable_table @source_schema='dbo', @source_name='Suppliers', @role_name=NULL, @supports_net_changes=0; END"

# Then retry connector registration
Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri http://localhost:8083/connectors -InFile ./connectors/sqlserver-source.json
```

Notes
-----
- If Connect returns 409, the connector already exists; use PUT to update.
- JDBC Sink depends on the Confluent JDBC connector bundled in Debezium Connect 3.2 images.
- Topics are prefixed with `suppliers` as configured; adjust sink `topics.regex` accordingly.

