# VPS delivery for golink

Run **VPS Release** from `main`. Preflight is read-only. Deployment requires an explicit full source commit and schema compatibility acknowledgment. Production target is 103.235.75.63; staging target is 103.160.37.37. Runtime credentials stay on the VPS. Environment-scoped `VPS_SSH_KEY` grants only this app's forced-command receiver; `VPS_HOST`, `VPS_USER`, `VPS_KNOWN_HOSTS` pin its destination.

The known deployed staging source before CI migration is `70070396604e8dba364cd49ed7af3690c46a5fce`. Do not replace staging isolation patches with a plain older staging/main commit. AWS deployment workflows stay disabled after the replacement is verified. No automatic schema reversal or production RC promotion occurs. A failed application rollout restores its prior image and layout.
