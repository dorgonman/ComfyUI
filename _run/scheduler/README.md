# ComfyUI Task Scheduler Runtime

This is the canonical Windows runtime for this workstation. It replaces the
legacy NSSM `ComfyUI` LocalSystem service and keeps one loopback endpoint:

    http://127.0.0.1:8188/

The scheduled task is `\Kano\GenAI\KanoComfyUI`, runs as the current
interactive user with limited privileges, starts at logon, and ignores duplicate
starts. Port 8191 is not a fallback.

## One-time migration

Run from an elevated PowerShell:

```powershell
& D:\Web\ComfyUI\_run\scheduler\migrate-from-service.ps1 -Profile shared
```

Migration registers the task first, stops the legacy service, starts and health
checks the scheduled runtime, then deletes the service. It restarts the legacy
service if scheduled startup fails before deletion.

## Lifecycle

```powershell
& D:\Web\ComfyUI\_run\scheduler\start-scheduler.ps1
& D:\Web\ComfyUI\_run\scheduler\status-scheduler.ps1
& D:\Web\ComfyUI\_run\scheduler\doctor-scheduler.ps1
& D:\Web\ComfyUI\_run\scheduler\stop-scheduler.ps1
& D:\Web\ComfyUI\_run\scheduler\unregister-scheduler.ps1 -Stop
```

`shared` is the default profile. `exclusive` performs a GPU-memory occupancy
guard before launch. Override its default 6144 MB threshold with
`KANO_COMFYUI_EXCLUSIVE_MAX_USED_MB`. Both profiles use the same models and
quality settings; exclusive is an admission policy, not a second server.

