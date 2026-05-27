# Curio - Smoke manual de notificacoes

Este smoke valida a entrega real das notificacoes fora do runner E2E. O E2E ja
cobre criacao, edicao, cancelamento, persistencia e fila nativa Android; este
roteiro confirma a notificacao aparecendo no sistema operacional.

## Artefatos

- Windows: `curio-windows-test.exe` da release ou o `.exe` gerado em
  `build\portable-exe`.
- Android: `curio-android-test.apk` da release ou
  `build\app\outputs\flutter-apk\app-release.apk`.

Anote antes de testar:

- versao do Curio
- Windows build ou modelo/versao do Android
- SHA256 do artefato testado
- horario local do teste

## Windows

Smoke automatico local:

```powershell
& '..\..\.tools\flutter\bin\flutter.bat' run -d windows -t tool\windows\smoke_windows_notifications.dart --no-pub
```

Resultado esperado no terminal:

```text
SMOKE_WINDOWS_NOTIFICATION_OK
```

Esse smoke dispara uma toast imediata, agenda uma notificacao futura, confirma
que ela entrou na fila nativa do Windows e cancela antes da entrega.

Smoke manual de interface:

1. Abra o `curio-windows-test.exe`.
2. Em `Hoje`, clique em `Nova notificacao`.
3. Crie uma notificacao para daqui a 2 minutos:
   - titulo: `Smoke Windows HH:mm`
   - mensagem: `Entrega local Windows`
   - data: hoje
   - horario: agora + 2 minutos
4. Salve e confirme que ela aparece em `Proximas notificacoes`.
5. Edite a notificacao e altere o titulo para `Smoke Windows editado HH:mm`.
6. Confirme que o titulo editado aparece e que o titulo antigo nao aparece mais.
7. Aguarde a entrega na area de trabalho/Action Center.
8. Clique na notificacao entregue e confirme que o Curio abre no dia correto.
9. Crie outra notificacao curta, cancele antes da hora e confirme que ela nao e
   entregue.

Resultado esperado:

- notificacao aparece no Windows no horario escolhido
- edicao substitui a notificacao anterior
- cancelamento impede entrega futura
- clique na notificacao leva ao conteudo do dia

## Android

1. Instale o APK em aparelho fisico ou emulador.
2. Abra o app.
3. Se o app nao tiver permissao de notificacoes ou alarme exato, tente criar uma
   notificacao e confirme que o Android abre a tela de autorizacao.
4. Conceda notificacoes e alarme/lembrete exato quando solicitado pelo sistema.
5. Volte ao Curio e crie uma notificacao para daqui a 2 minutos:
   - titulo: `Smoke Android HH:mm`
   - mensagem: `Entrega local Android`
   - data: hoje
   - horario: agora + 2 minutos
6. Salve e confirme que ela aparece em `Proximas notificacoes`.
7. Edite o titulo para `Smoke Android editado HH:mm`.
8. Aguarde a entrega na bandeja de notificacoes.
9. Toque na notificacao entregue e confirme que o Curio abre no dia correto.
10. Crie outra notificacao curta, cancele antes da hora e confirme que ela nao e
    entregue.

Resultado esperado:

- o app so pede autorizacao se a permissao estiver ausente
- com permissao concedida, o editor inline abre direto
- notificacao aparece no Android no horario escolhido
- edicao substitui a notificacao anterior
- cancelamento impede entrega futura
- toque na notificacao leva ao conteudo do dia

## Registro

Use este formato para registrar o smoke:

```text
Artefato:
SHA256:
Sistema:
Horario local:

Windows:
- Criar:
- Editar:
- Entregar:
- Abrir pelo clique:
- Cancelar:

Android:
- Permissoes:
- Criar:
- Editar:
- Entregar:
- Abrir pelo toque:
- Cancelar:

Observacoes:
```
