# Prontidão OAuth para importar/exportar calendários

Este roteiro cobre a autorização de terceiros para importar ou exportar eventos
do Google Calendar e do Outlook/Microsoft 365.

Curió não tem login próprio. A sincronização entre Windows e Android continua
sendo local-first e opcionalmente self-hosted. OAuth é apenas uma ponte
temporária com o calendário externo quando o usuário toca em importar ou
exportar. A troca manual por `.ics` permanece como fallback para Google
Calendar, Outlook e qualquer calendário compatível.

## O que já fica pronto no app

- Client IDs públicos podem entrar por `--dart-define`.
- A tela `Sync` mostra a prontidão de Google Calendar e Outlook/Microsoft 365
  para importação/exportação.
- Nenhum client secret, access token ou refresh token deve ir para o GitHub.
- A autorização acontece no navegador oficial do provedor.
- O access token deve existir apenas em memória durante a operação e ser
  descartado ao terminar.

## Build com Client IDs públicos

Windows:

```powershell
..\..\.tools\flutter\bin\flutter.bat build windows --release --no-pub `
  --dart-define=CURIO_GOOGLE_WINDOWS_CLIENT_ID="cole-o-client-id-windows" `
  --dart-define=CURIO_MICROSOFT_CLIENT_ID="cole-o-client-id-microsoft" `
  --dart-define=CURIO_MICROSOFT_TENANT="common"
```

Android:

```powershell
..\..\.tools\flutter\bin\flutter.bat build apk --release --no-pub `
  --dart-define=CURIO_GOOGLE_ANDROID_CLIENT_ID="cole-o-client-id-android" `
  --dart-define=CURIO_MICROSOFT_CLIENT_ID="cole-o-client-id-microsoft" `
  --dart-define=CURIO_MICROSOFT_TENANT="common"
```

`CURIO_MICROSOFT_TENANT` pode ser `common`, `consumers`, `organizations` ou o
ID de um tenant específico. Para uso pessoal com Outlook.com e Microsoft 365,
`common` é o padrão mais flexível.

Os scripts de pacote também leem essas mesmas variáveis de ambiente:

```powershell
$env:CURIO_GOOGLE_WINDOWS_CLIENT_ID = "cole-o-client-id-windows"
$env:CURIO_GOOGLE_ANDROID_CLIENT_ID = "cole-o-client-id-android"
$env:CURIO_MICROSOFT_CLIENT_ID = "cole-o-client-id-microsoft"
$env:CURIO_MICROSOFT_TENANT = "common"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\package-portable.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\android\build-release-appbundle.ps1
```

## Validação sob demanda

Quando a importação/exportação direta for ligada no app:

1. O usuário toca em importar ou exportar via Google/Microsoft.
2. O Curió abre o navegador do sistema.
3. O provedor mostra a tela de consentimento cadastrada no console.
4. O app recebe o authorization code pelo redirect registrado.
5. O code é trocado por tokens usando Authorization Code + PKCE.
6. O access token é usado apenas para ler/criar/atualizar eventos da operação.
7. O Curió converte os eventos para notas/notificações ou envia os eventos
   criados a partir das notas/notificações.
8. O token é descartado. Não existe sessão Curió nem estado de login do app.

Esse fluxo é obrigatório porque Windows e Android são public clients: eles não
podem provar identidade usando segredo embutido.

## Publicação e consentimento

### Google

- Console: Google Cloud Console.
- API: `Google Calendar API`.
- Escopo mínimo: `https://www.googleapis.com/auth/calendar.events`.
- Enquanto o app estiver privado, manter o OAuth consent screen em modo de
  teste e adicionar o e-mail do usuário como test user.
- Para distribuição pública, preencher domínio, política de privacidade,
  justificativa do escopo e verificação exigida pelo Google.
- Android precisa do SHA-1 do certificado de distribuição. Builds vindas da
  Play Store usam o certificado de app signing da Play, não a upload key local.

### Microsoft

- Console: Microsoft Entra admin center.
- App registration: `Curió`.
- Público sugerido: contas organizacionais e contas pessoais Microsoft.
- Redirect nativo sugerido:
  `https://login.microsoftonline.com/common/oauth2/nativeclient`.
- Permissões delegadas:
  - `User.Read`
  - `Calendars.ReadWrite`
- Após alterar permissões, testar a tela de consentimento em uma conta pessoal
  Outlook.com e em uma conta Microsoft 365, se esse público for mantido.

## Critério de pronto

- `docs/calendar-app-registration.md` contém os Client IDs criados.
- O build foi gerado com os `--dart-define` corretos.
- A tela `Sync` mostra Google e Microsoft como configurados.
- `.ics` continua exportando/importando notas e notificações.
- Importar/exportar abre a tela oficial do provedor.
- Nenhum refresh token é persistido pelo Curió.
- O sync self-hosted continua independente do OAuth.

## Referências oficiais

- Google OAuth para apps instalados:
  https://developers.google.com/identity/protocols/oauth2/native-app
- Google Calendar Events API:
  https://developers.google.com/workspace/calendar/api/v3/reference/events
- Microsoft public/confidential clients:
  https://learn.microsoft.com/en-us/entra/identity-platform/msal-client-applications
- Microsoft redirect URI:
  https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-redirect-uri
- Microsoft Graph event:
  https://learn.microsoft.com/en-us/graph/api/resources/event
