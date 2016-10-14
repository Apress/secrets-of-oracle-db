-- run with SYSDBA privileges
ALTER SYSTEM SET pga_aggregate_target=10m scope=memory;
@auto_pga_parameters.sql
ALTER SYSTEM SET pga_aggregate_target=32m scope=memory;
@auto_pga_parameters.sql
ALTER SYSTEM SET pga_aggregate_target=64m scope=memory;
@auto_pga_parameters.sql
ALTER SYSTEM SET pga_aggregate_target=128m scope=memory;
@auto_pga_parameters.sql
ALTER SYSTEM SET pga_aggregate_target=256m scope=memory;
@auto_pga_parameters.sql
ALTER SYSTEM SET pga_aggregate_target=512m scope=memory;
@auto_pga_parameters.sql
ALTER SYSTEM SET pga_aggregate_target=1g scope=memory;
@auto_pga_parameters.sql
ALTER SYSTEM SET pga_aggregate_target=2g scope=memory;
@auto_pga_parameters.sql
ALTER SYSTEM SET pga_aggregate_target=3g scope=memory;
@auto_pga_parameters.sql
ALTER SYSTEM SET pga_aggregate_target=4g scope=memory;
@auto_pga_parameters.sql
ALTER SYSTEM SET pga_aggregate_target=8g scope=memory;
@auto_pga_parameters.sql
ALTER SYSTEM SET pga_aggregate_target=16g scope=memory;
@auto_pga_parameters.sql
ALTER SYSTEM SET pga_aggregate_target=32g scope=memory;
@auto_pga_parameters.sql
