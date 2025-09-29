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
docker exec -it demo_postgres psql -U postgres -d suppliers_replica -c '\dt'
docker exec -it demo_postgres psql -U postgres -d suppliers_replica -c 'SELECT * FROM "suppliers_suppliersdb_dbo_suppliers";'
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

Troubleshooting
---------------
- Connect exited 137: reduce heap and memory in `docker-compose.yml` for `connect` (e.g., `KAFKA_HEAP_OPTS=-Xms256m -Xmx768m`, `mem_limit: 1g`).
- Kafka CLI not found: use `docker exec -it dbz_kafka bash bin/...` paths.
- Source validation: if CDC not enabled, run the force-enable command above; then delete/recreate the connector.
- SQL Server permissions: seed creates `debezium` login, grants `VIEW SERVER STATE`, `db_owner`, and access to `cdc` and `dbo` schemas.
- Sink registration: use Debezium class `io.debezium.connector.jdbc.JdbcSinkConnector`; for updates via PUT, send only `.config` JSON.
- Signals NPE: we removed `signal.data.collection` from the source; add later with correct table naming if needed.

Notes
-----
- If Connect returns 409, the connector already exists; use PUT to update.
- JDBC Sink depends on the Confluent JDBC connector bundled in Debezium Connect 3.2 images.
- Topics are prefixed with `suppliers` as configured; adjust sink `topics.regex` accordingly.

## Productionizing: On‑prem SQL Server → AWS MSK → AWS RDS Postgres

### Architecture
- Use AWS MSK (managed Kafka) in a private VPC.
- Run Kafka Connect via MSK Connect (managed) or self‑managed on EKS/EC2 (2–3 workers for HA).
- Source: Debezium SQL Server connector; Sink: Debezium JDBC Sink to RDS Postgres.

### Networking & Security
- Connectivity from on‑prem to VPC via Site‑to‑Site VPN or Direct Connect.
- Restrict Security Groups: SQL Server (1433) from Connect subnets; Connect ↔ MSK brokers (TLS); Connect → RDS (5432/TLS).
- TLS everywhere: SQL Server `encrypt=true` with proper CA; MSK broker TLS; Postgres `sslmode=require/verify-full`.
- Secrets in AWS Secrets Manager or SSM Parameter Store; reference from MSK Connect or K8s Secrets.

### SQL Server (on‑prem) prerequisites
- Enable CDC at DB level and for target tables; ensure SQL Server Agent is running.
- Create `debezium` login with: server `VIEW SERVER STATE`; database `db_owner` (or explicit `cdc`/table grants).
- Verify capture instances: `EXEC sys.sp_cdc_help_change_data_capture;`.

### Kafka: MSK setup
- Create topics (or let Debezium auto‑create) with RF=3, partitions sized for throughput.
- Internal topics (connect configs/offsets/status, schema history) RF=3, compacted.
- Consider Avro + (Glue) Schema Registry, or keep JSON with schemas.

### Kafka Connect (MSK Connect recommended)
- Source config (key points):
  - `connector.class=io.debezium.connector.sqlserver.SqlServerConnector`
  - `database.hostname/port/user/password`, `database.names`, `table.include.list`
  - `topic.prefix`, `snapshot.mode=initial` (first run) or `no_data` for subsequent deploys
  - Remove `signal.data.collection` unless you need runtime control
- Sink config (key points):
  - `connector.class=io.debezium.connector.jdbc.JdbcSinkConnector`
  - `connection.url=jdbc:postgresql://<rds-endpoint>:5432/<db>?sslmode=require`
  - `connection.username/password`
  - `topics.regex` (or `topics`) mapping to your topics
  - `primary.key.mode=record_key`, `primary.key.fields=Id`, `insert.mode=upsert`, `delete.enabled=true`
  - `schema.evolution=basic`, `consumer.override.auto.offset.reset=earliest` (bootstrap)

### AWS RDS Postgres
- Create least‑privilege user for the sink; enforce SSL.
- Size instance/IOPS for ingest; monitor connections and write throughput.

### Observability
- Expose JMX from Connect → Prometheus → Grafana (task state, lag, error rates).
- Centralize logs (CloudWatch for MSK Connect).
- Alerts for task FAILED, rising lag, error spikes.

### Operations
- Keep connector JSON in Git; deploy via MSK Connect APIs (or GitOps on EKS).
- Use POST to create, PUT with `.config` to update; version configs.
- Backups/DR: MSK across 3 AZs; RDS backups/snapshots; IaC (Terraform/CFN).

### Hardening
- Principle of least privilege on SQL Server, Kafka ACLs, and Postgres.
- Prefer disabling signals; if used, lock down the channel (table perms or Kafka ACLs).

### Cutover checklist (condensed)
1. Provision MSK (+ private subnets, SGs), RDS Postgres.
2. Establish on‑prem connectivity to VPC; open required ports.
3. Enable CDC on SQL Server; verify capture instances.
4. Deploy source connector (snapshot initial), then sink connector.
5. Verify snapshot in RDS; switch to streaming; monitor lag and errors.
6. Document runbooks and alerts.

