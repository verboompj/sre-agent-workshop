# VM Workshop Scripts

| Path | Purpose |
|------|---------|
| `setup.ps1` | Pre-workshop prereq checks |
| `cleanup.ps1` | Resource group teardown helper |
| `access/start-http-tunnel.ps1` | Bastion HTTP tunnel to a workshop VM |
| `access/start-rdp-tunnel.ps1` | Bastion RDP tunnel (defaults to user `azureuser`) |
| `access/start-bastion-tunnel.sh` | Cross-platform tunnel helper (optional 6th arg: VM username) |
| `../scenarios/<id>/` | Per-scenario fault injectors and constrained remediations (run via the approval wrapper) |
| `validation/smoke-test.ps1` | Bastion tunnel + HTTP smoke check |

