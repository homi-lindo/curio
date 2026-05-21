# Curió self-hosted sync

Este kit sobe apenas o servidor de sincronização. Ele não envia notificações:
Windows e Android continuam agendando alertas localmente em cada dispositivo.

## Arquivos do kit

- `compose.yaml`: serviço Docker Compose.
- `Dockerfile.sync`: build do servidor Dart.
- `.env.example`: modelo de configuração local.
- `server/`: API HTTP `/health`, `/snapshot` e `/sync`.
- `packages/lume_core/`: domínio e merge usados pelo servidor.

## Uso local

```powershell
Copy-Item .env.example .env
# Edite .env e defina LUME_SYNC_TOKEN com pelo menos 16 caracteres.
docker compose --env-file .env up -d --build
docker compose logs -f curio-sync
```

No app, use o endereço do host sem caminho:

```text
http://<ip-da-maquina>:8787
```

Use o mesmo token salvo em `.env`.

## HTTPS

Builds release do app rejeitam HTTP simples. Para Windows + Android em release,
publique o servidor atrás de HTTPS ou monte certificados PEM no container:

```yaml
volumes:
  - curio-sync-data:/data
  - ./certs:/certs:ro
environment:
  LUME_SYNC_TLS_CERT: /certs/cert.pem
  LUME_SYNC_TLS_KEY: /certs/key.pem
```

Certificados autoassinados precisam ser confiáveis no Windows e no Android antes
de o app aceitar o endpoint.

## Publicação no GitHub

O script `tool/sync/package-self-hosted-kit.ps1` gera um zip pronto para anexar
a uma GitHub Release. Depois das credenciais, publique esse zip como artefato de
release do repositório.
