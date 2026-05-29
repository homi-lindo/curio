# Curió

Curió é um app pessoal, local-first, para Windows e Android. O foco atual é
simples: notas diárias, notas gerais, notificações locais confiáveis, backup
legível e sincronização opcional.

O projeto ainda está em fase de teste privado. A prioridade é usabilidade,
robustez, rapidez e um visual elegante, sem fluxo comercial.

## Escopo atual

- App Flutter para Windows e Android.
- Abas Hoje, Agenda, Quadro, Notas, Tarefas e Sync.
- Hoje mostra notas e próximas notificações do dia, com salto direto para a
  edição.
- Agenda mensal com seleção inline de ano/mês/dia e abertura da edição do dia.
- Quadro mensal com cards apenas para dias que possuem nota ou notificação.
- Notas diárias e gerais com editor Markdown, barra de formatação e atalhos de
  teclado.
- Lista de tarefas simples com filtros (abertas, hoje, com hora, feitas, todas),
  data/hora opcional, conclusão por checkbox e criação direta a partir da nota
  selecionada.
- Pesquisa global de texto em notas e notificações.
- Criação e edição inline de notificações, com título, data e hora editáveis.
- Autosave das notas e histórico local de até 50 versões anteriores.
- Backup manual em `.txt`, legível por humanos, com restauração funcional de
  notas e notificações.
- Zoom de página de 20% a 200%, com suporte a gestos no Android, `Ctrl +`,
  `Ctrl -`, `Ctrl + rolagem` e reset de zoom.
- Detecção automática de tema claro/escuro do sistema.
- Temas Aurora, Slate e Lumen.
- Notificações locais com `flutter_local_notifications`.
- Android com permissão de alarme exato, recuperação após reboot e redirecionamento
  para as autorizações do sistema quando necessário.
- Windows com identidade/AUMID no pacote instalado e atalho do portátil para
  toasts mais confiáveis.
- Banco local SQLite gerado com Drift.
- Identidade local persistente por instalação.
- Sincronização opcional por servidor self-hosted em Docker ou endpoint HTTPS
  próprio. Notas, tarefas e lembretes sincronizam entre Windows e Android; cada
  aparelho reagenda os próprios alarmes localmente.
- Kit self-hosted publicado em release GitHub.
- Prontidão OAuth apenas para importar/exportar calendários externos: Client
  IDs públicos por `--dart-define`, UI de status em Sync e sem login no Curió.
- Testes unitários e E2E Android cobrindo fluxos principais de notas,
  notificações, backup, sync e navegação.

## Arquitetura

- As notificações são agendadas localmente em cada dispositivo. O servidor de
  sync apenas replica dados; ele não dispara notificações.
- `ReminderIntent` é a intenção sincronizável do lembrete (o quê, quando,
  recorrência, fuso, título e mensagem). É ele que viaja entre dispositivos.
- `ScheduledNotificationRecord` é a projeção local usada para agendamento no
  dispositivo e não é sincronizado; cada aparelho mantém os próprios IDs de
  notificação.
- A reconciliação local (`_reconcileReminders`) roda no boot e após cada sync:
  agenda no SO qualquer `ReminderIntent` habilitado que este aparelho ainda não
  agendou e cancela notificações cujo lembrete foi removido/desligado em outro
  aparelho. Com vários aparelhos ligados, o lembrete toca em todos. Lembretes
  diários/semanais disparam no horário-relógio local de cada aparelho.
- Chaves de ocorrência únicas usam o instante UTC em ISO.
- Ocorrências diárias e semanais usam a data local (`YYYY-MM-DD`).
- IDs de notificação são hashes estáveis de dispositivo, lembrete e ocorrência.
- `LocalTimeZoneResolver` mapeia nomes comuns de timezone, incluindo o timezone
  do Windows para Brasília, antes do agendamento.
- `DeviceIdentityStore` grava `lume-device.json` ao lado do banco local para
  preservar um ID estável de sincronização.
- `SnapshotSyncMerger` mescla notas, tarefas, lembretes (`ReminderIntent`) e
  tombstones, preservando edições mais novas (last-writer-wins por
  `updatedAtUtc`) e impedindo que registros apagados voltem por sync antigo.
- `compactSnapshot` limita o crescimento do estado a longo prazo: descarta
  tombstones com mais de 180 dias (`kTombstoneRetention`) e lembretes one-shot
  já disparados há mais de 30 dias (`kFiredReminderRetention`). Lembretes
  recorrentes são sempre preservados. Roda no boot do app e no servidor antes
  de gravar. A janela de 180 dias é a margem de segurança para um aparelho que
  fique meses offline ainda receber a exclusão antes de o tombstone sumir.
- `packages/lume_core` contém os modelos e a lógica de merge compartilhados pelo
  app Flutter e pelo servidor Dart/Docker.
- `HttpSyncAdapter` envia snapshots para `/sync` e usa o cabeçalho
  `x-lume-sync-token` quando um token está configurado.
- `HttpSyncAdapter` suporta pinning por impressão digital SHA-256
  (`SyncSettings.pinnedCertSha256`): com um pin, um certificado autoassinado é
  aceito — e só ele. `SyncPairing` (em `lume_core`) é o código de pareamento
  compartilhado (origem + token + impressão digital) que o servidor imprime e o
  app cola. Sem pin, vale a validação padrão de CA.
- Builds release de Windows e Android recusam URLs HTTP para sync remoto. Use
  HTTP apenas em debug ou em ambiente local controlado.
- O servidor Docker grava estado em `/data/server-state.json`, com arquivo
  temporário e `.bak` para recuperação após escrita interrompida.
- O servidor local no Windows é um helper iniciado pelo usuário, fica em primeiro
  plano dentro do processo Flutter e exige o mesmo token.
- O estado local principal fica em `lume.sqlite` no diretório de suporte da
  plataforma.
- Dados antigos em `lume-state.json` são importados automaticamente no primeiro
  uso quando o SQLite ainda está vazio.

Os nomes internos `lume` e `LUME_*` ainda existem em alguns arquivos por
compatibilidade de pacote, banco e variáveis de ambiente. O nome do app e dos
artefatos publicados é Curió.

## Comandos úteis

Execute a partir de `apps/lume`:

```powershell
..\..\.tools\flutter\bin\dart.bat format lib test integration_test packages server
..\..\.tools\flutter\bin\dart.bat run build_runner build
..\..\.tools\flutter\bin\flutter.bat analyze --no-pub
..\..\.tools\flutter\bin\flutter.bat test --no-pub
..\..\.tools\flutter\bin\flutter.bat test integration_test/app_test.dart -d 127.0.0.1:5555 --no-pub --timeout 120s
```

Para build Android de teste:

```powershell
..\..\.tools\flutter\bin\flutter.bat build apk --release --no-pub
```

Para conferir a configuração pública de OAuth dos calendários:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\calendar\check-oauth-readiness.ps1
```

Os scripts `tool\windows\package-portable.ps1` e
`tool\android\build-release-appbundle.ps1` repassam automaticamente as variáveis
`CURIO_GOOGLE_WINDOWS_CLIENT_ID`, `CURIO_GOOGLE_ANDROID_CLIENT_ID`,
`CURIO_MICROSOFT_CLIENT_ID` e `CURIO_MICROSOFT_TENANT` quando elas existirem.

Para gerar o App Bundle da Play:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\android\build-release-appbundle.ps1
```

Para empacotar o EXE portátil de teste do Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\package-portable-exe.ps1
```

Para gerar o MSIX:

```powershell
$env:LUME_MSIX_CERTIFICATE_THUMBPRINT = "<thumbprint-do-certificado>"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\package-msix.ps1
```

Para rodar o WACK:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\run-wack.ps1
```

Se o terminal não estiver elevado:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\run-wack-admin.ps1
```

## Sync self-hosted

O app não precisa de Docker para funcionar. Docker é apenas para o servidor
opcional de sincronização, útil quando Windows e Android precisam compartilhar
conteúdo por um endpoint próprio.

Use o mesmo token no app e no servidor. Prefira `LUME_SYNC_TOKEN` para não
expor segredo no histórico do shell. O token deve ter pelo menos 16 caracteres.

Servidor direto, sem Docker:

```powershell
Push-Location server
$env:LUME_SYNC_TOKEN = "escolha-um-token-longo"
..\..\..\.tools\flutter\bin\dart.bat run bin\lume_sync_server.dart --host 0.0.0.0 --port 8787
Pop-Location
```

### HTTPS plug-and-play (certificado do próprio app + pinning)

O app exige HTTPS para sync remoto em builds release. Para não depender de
domínio/CA nem de proxy reverso, o servidor usa um certificado autoassinado e o
app confia nele pela **impressão digital** (pinning, no estilo SSH): você cola
uma vez o **código de pareamento** que o servidor mostra ao iniciar, e o app
passa a aceitar exatamente aquele certificado.

Docker (recomendado): já é automático. Na primeira execução o servidor gera o
certificado no volume de dados e imprime o código. Defina o host acessível para
o código sair completo:

```powershell
$env:LUME_SYNC_TOKEN = "escolha-um-token-longo"
$env:LUME_SYNC_PUBLIC_HOST = "192.168.0.10"   # IP/hostname que os aparelhos usam
docker compose --env-file .env up -d --build
docker compose logs curio-sync   # copie a linha "Pairing code (cole no app): ..."
```

Windows direto (sem Docker): gere o certificado e o código com o helper:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\sync\gen-cert.ps1 -PublicHost 192.168.0.10 -Token "escolha-um-token-longo"
Push-Location server
$env:LUME_SYNC_TOKEN = "escolha-um-token-longo"
..\..\..\.tools\flutter\bin\dart.bat run bin\lume_sync_server.dart --host 0.0.0.0 --port 8787 --tls-cert ..\.lume-sync\cert.pem --tls-key ..\.lume-sync\key.pem --public-host 192.168.0.10
Pop-Location
```

No app, aba Sync → **Pareamento rápido** → cole o `curio-pair...`. Ele preenche
servidor, token e fixa o certificado. Se o servidor estiver em `0.0.0.0` sem
`LUME_SYNC_PUBLIC_HOST`, ele imprime só a impressão digital — preencha o
servidor/token manualmente e cole a impressão no mesmo campo.

Alternativa com CA pública: se preferir um certificado de uma autoridade
confiável (ex.: proxy reverso Caddy/Nginx/Traefik com Let's Encrypt), use-o sem
pinning — basta deixar o campo de pareamento vazio. HTTP puro só é aceito em
debug ou em LAN confiável (com aviso explícito do servidor).

Docker:

```powershell
Copy-Item .env.example .env
# Edite .env e defina um LUME_SYNC_TOKEN longo.
docker compose --env-file .env up -d --build
docker compose logs -f curio-sync
```

Use somente a origem do servidor no app:

```text
https://seu-dominio-ou-ip:8787
```

Comandos úteis:

```powershell
docker compose ps
docker compose down
docker compose down --volumes
```

Para gerar o zip self-hosted publicado na release:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\sync\package-self-hosted-kit.ps1
```

## Downloads de teste

Os artefatos públicos ficam em GitHub Releases:

- `curio-windows-test.exe`: versão portátil para testar no Windows sem instalar
  MSIX.
- `curio-windows-installer.msix`: instalador Windows para sideload/teste.
- `curio-android-test.apk`: APK completo para instalação direta no Android.
- `curio-android-play-store.aab`: bundle para Play Console.
- `curio-self-host.zip`: kit Docker/Compose do servidor opcional.
- `curio-social-preview.png`: imagem 1280x640 para social preview do GitHub.
- `docs/calendar-app-registration.md`: roteiro de registro OAuth para Google
  Calendar e Microsoft Graph/Outlook.
- `docs/calendar-oauth-readiness.md`: roteiro de autorização sob demanda para
  importação/exportação e publicação/consentimento.

Release atual:

```text
https://github.com/homi-lindo/curio/releases/tag/v1.0.22-23
```

## Prontidão de loja

Checklist principal:

- Android release exige `android/key.properties`.
- Sync em release exige HTTPS.
- Play Store exige declaração de uso de alarme exato.
- Smoke manual de notificações deve seguir `docs/smoke-notificacoes.md`.
- Android Gradle Plugin está fixado em `8.11.1` em `android/settings.gradle.kts`
  (piso recomendado do Flutter 3.44). O AGP 9 torna o Kotlin embutido o padrão,
  ainda não suportado por plugins como `file_picker`; revisar o pin quando os
  plugins migrarem (guia: docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin).
- Sem alerta do SmartScreen no Windows exige assinatura por CA confiável
  (certificado EV dá reputação imediata; OV ganha reputação com o tempo) ou
  publicação pela Microsoft Store, que assina o pacote. Certificado autoassinado
  sempre dispara o alerta. O WACK valida o pacote, não a confiança do SmartScreen.
- MSIX deve ser validado no WACK em PowerShell elevado antes do envio final.
- A política de privacidade base está em `docs/privacy-policy.md`.
- As notas de submissão ficam em `docs/store-submission-notes.md`,
  `docs/store-review-evidence.md` e
  `docs/play-store-procedimento-permissoes.md`.

Gate local:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\verify-release-readiness.ps1
```

Gate estrito antes de loja:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\verify-release-readiness.ps1 -Strict
```

## Pendências conhecidas

- AGP fixado em 8.11.1 de propósito. Migrar para AGP 9 (built-in Kotlin)
  **quando o `file_picker` publicar uma versão que use built-in Kotlin** — hoje
  ele ainda aplica o `org.jetbrains.kotlin.android` legado, o único bloqueador
  (nosso código e `audioplayers` já estão prontos). Na migração: `flutter pub
  upgrade file_picker`, `android.builtInKotlin=true`, remover a declaração
  `org.jetbrains.kotlin.android` de `android/settings.gradle.kts` e mover
  `kotlin { compilerOptions }` para o DSL do AGP.
- Rodar WACK final em PowerShell elevado no MSIX que será enviado.
- Testar o APK em aparelho Android físico além do emulador.
- Enviar o AAB no Play Console e preencher a declaração de alarme exato.
- Subir `curio-social-preview.png` no GitHub em Settings -> Social preview; a API
  pública do GitHub não expõe upload dessa imagem.
- Decidir se a próxima publicação deve manter a tag `v1.0.22-23` ou criar uma
  nova tag de release para evitar mover tag já publicada.
