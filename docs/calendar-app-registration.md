# Registro do app para calendários Google e Microsoft

Este documento fixa os dados de registro do Curió para a integração direta
com Google Calendar e Outlook/Microsoft Graph. A troca por arquivo `.ics`
já funciona sem credenciais; OAuth é necessário apenas para sincronização
direta com as contas do usuário.

## Identidade do Curió

- Nome público: `Curió`
- Android package name: `app.lume.personal`
- Windows AppUserModelID / MSIX identity: `App.Lume.Personal`
- Versão atual: `1.0.22+23`
- Site/repositório: `https://github.com/homi-lindo/curio`

## Google Cloud

Documentação base:

- OAuth para apps instalados: https://developers.google.com/identity/protocols/oauth2/native-app
- Criar credenciais Workspace: https://developers.google.com/workspace/guides/create-credentials
- Eventos do Calendar API: https://developers.google.com/workspace/calendar/api/v3/reference/events

### Projeto e APIs

1. Acesse Google Cloud Console.
2. Crie ou selecione um projeto chamado `Curio`.
3. Ative a API `Google Calendar API`.
4. Configure a tela de consentimento OAuth.
5. Enquanto o app estiver privado, mantenha em modo de teste e adicione seu
   e-mail como test user.

### Escopos

Para a integração completa de leitura/escrita de eventos:

```text
https://www.googleapis.com/auth/calendar.events
```

Esse escopo permite criar, ler, atualizar e remover eventos do calendário do
usuário. Ele é mais restrito que `https://www.googleapis.com/auth/calendar`.

### Client ID para Windows

Crie uma credencial OAuth do tipo:

```text
Application type: Desktop app
Name: Curio Windows
```

O fluxo de desktop deve usar navegador do sistema + PKCE + redirect por
loopback (`127.0.0.1`) quando a implementação OAuth for adicionada ao app.
Não grave client secret em código-fonte.

### Client ID para Android

Crie uma credencial OAuth do tipo:

```text
Application type: Android
Name: Curio Android
Package name: app.lume.personal
SHA-1 certificate fingerprint: ver abaixo
```

Para build local de debug, o fingerprint atual é:

```text
29:D2:4E:0D:2D:12:12:7F:4E:35:5C:EB:37:72:4E:90:B5:94:D7:CF
```

Para a upload key local de release, o fingerprint atual é:

```text
D2:7B:C8:D7:6B:DD:38:B7:C3:CE:18:C8:25:46:E7:0C:2D:4E:EE:BC
```

Para produção na Play Store, use o SHA-1 do `App signing certificate` no Play
Console. O SHA-1 da upload key só serve para builds assinadas localmente; apps
baixados pela Play usam o certificado de app signing do Google Play.

Rode este script para imprimir os valores locais disponíveis:

```powershell
.\tool\android\print-oauth-registration-values.ps1
```

## Microsoft Entra / Outlook

Documentação base:

- Registrar redirect URI: https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-redirect-uri
- Limites e regras de redirect URI: https://learn.microsoft.com/en-us/entra/identity-platform/reply-url
- Recurso de evento no Microsoft Graph: https://learn.microsoft.com/en-us/graph/api/resources/event
- Permissões Microsoft Graph: https://learn.microsoft.com/en-us/graph/permissions-reference

### Registro

1. Acesse Microsoft Entra admin center.
2. Entre em `App registrations` e crie um app:

```text
Name: Curió
Supported account types: Accounts in any organizational directory and personal Microsoft accounts
```

Escolha esse público se quiser suportar tanto Microsoft 365 corporativo quanto
Outlook.com pessoal. Se o uso for apenas pessoal, `Personal Microsoft accounts
only` também basta.

### Plataformas

Adicione plataformas de autenticação:

```text
Mobile and desktop applications
Suggested redirect URI: https://login.microsoftonline.com/common/oauth2/nativeclient
```

Para Android com MSAL, adicione também:

```text
Platform: Android
Package name: app.lume.personal
Signature hash: ver script abaixo
```

Hash de assinatura do debug atual:

```text
KdJODS0SEn9ONVzrN3JOkLWU188=
```

Hash de assinatura da upload key local de release:

```text
0nvI12vdOLfDzhjIJUbnDC1O7rw=
```

O hash de produção deve ser calculado a partir do certificado usado para a
build que será distribuída ao usuário final.

### API permissions

Use permissões delegadas, porque o app age em nome do usuário conectado:

```text
Microsoft Graph / Delegated:
- User.Read
- Calendars.ReadWrite
- offline_access
```

`Calendars.ReadWrite` permite criar, ler, atualizar e excluir eventos nos
calendários do usuário. `offline_access` permite renovar tokens sem pedir login
em toda abertura.

## Onde guardar os IDs

Não grave tokens, client secrets ou refresh tokens no repositório. O próximo
passo de implementação deve guardar:

- client IDs em configuração pública do app ou settings locais;
- access/refresh tokens no armazenamento seguro já usado pelo Curió;
- estado de sync por provedor fora das notas visíveis ao usuário.

Template local para os client IDs:

```json
{
  "google": {
    "windowsDesktopClientId": "",
    "androidClientId": "",
    "scopes": ["https://www.googleapis.com/auth/calendar.events"]
  },
  "microsoft": {
    "clientId": "",
    "tenant": "common",
    "scopes": ["User.Read", "Calendars.ReadWrite", "offline_access"]
  }
}
```

## Decisões de segurança

- Usar navegador do sistema, não WebView embutida.
- Usar Authorization Code + PKCE.
- Não embutir client secret.
- Solicitar apenas escopos de calendário necessários.
- Marcar eventos criados pelo Curió com metadados locais/extended properties
  para evitar duplicatas em importações futuras.
- Manter `.ics` como fallback manual, mesmo depois do OAuth direto.
