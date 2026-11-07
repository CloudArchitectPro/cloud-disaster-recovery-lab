# Windows PowerShell 7

The Phase 1 lab starts with Docker Compose and does not require a PowerShell recovery script. Run these **native PowerShell commands** from the repository root:

```powershell
$compose = 'infrastructure/docker/compose.yaml'
docker compose -f $compose config
docker compose -f $compose up -d --wait
docker compose -f $compose exec -T source psql -U lab_owner -d labdb -c 'SELECT count(*) FROM lab.assets;'
docker compose -f $compose exec -T recovery psql -U lab_owner -d labdb -c 'SELECT current_database();'
docker compose -f $compose down
```

Never use `down -v` unless you intentionally want to erase **both disposable lab volumes**. Backup and restore PowerShell scripts are **not implemented** in Phase 1.
