# Curió - Procedimento Play Store: permissões e alarmes

Este documento é o material em português para enviar o Curió ao Google Play
Console, especialmente por causa de notificações locais e alarme exato.

## Situação atual do app

O manifesto Android declara:

- `android.permission.INTERNET`
- `android.permission.POST_NOTIFICATIONS`
- `android.permission.RECEIVE_BOOT_COMPLETED`
- `android.permission.SCHEDULE_EXACT_ALARM`
- `android.permission.VIBRATE`

O app não declara:

- `android.permission.USE_EXACT_ALARM`
- `android.permission.USE_FULL_SCREEN_INTENT`
- permissões de localização
- permissões de SMS ou chamadas
- permissão ampla de arquivos como `MANAGE_EXTERNAL_STORAGE`

Essa é a posição mais segura para a Play Store: o Curió usa
`SCHEDULE_EXACT_ALARM`, que exige autorização do usuário no sistema, e evita
`USE_EXACT_ALARM`, que é mais restrita e indicada apenas para apps claramente
centrados em alarme, timer ou calendário.

## Fluxo correto no Play Console

1. Gerar o Android App Bundle de release (`.aab`).
2. Entrar no Google Play Console.
3. Abrir o app Curió.
4. Criar uma versão em `Teste interno` primeiro.
5. Enviar o arquivo `app-release.aab`.
6. Aguardar a análise automática do bundle.
7. Abrir `Conteúdo do app`.
8. Resolver o alerta de `Declaração de permissões`, se aparecer.
9. No formulário, selecionar a funcionalidade principal ligada a agenda,
   calendário, lembretes ou notificações no horário escolhido pelo usuário.
10. Colar o texto de declaração abaixo.
11. Informar que todo o app fica acessível sem login especial.
12. Anexar um vídeo curto demonstrando a criação de nota e notificação.
13. Enviar para revisão.

## Texto pronto: declaração de alarme exato

Use este texto no formulário de permissões da Play:

> O Curió é um aplicativo pessoal de notas, agenda e notificações locais. O
> usuário cria manualmente notas diárias e pode adicionar notificações com
> título, data e horário específicos. A permissão `SCHEDULE_EXACT_ALARM` é usada
> somente para entregar essas notificações locais no horário escolhido pelo
> usuário. Esse recurso é uma funcionalidade principal e visível do app. O Curió
> não usa alarmes exatos para publicidade, rastreamento, analytics, sincronização
> em segundo plano ou notificações promocionais. Se o usuário não conceder a
> autorização de alarme exato, o app continua funcionando para notas e agenda,
> mas não cria aquela notificação exata até que a autorização seja concedida.

## Texto pronto: instruções para o revisor

Use este texto em "Instruções para análise":

> Não é necessário login. Para verificar a funcionalidade:
>
> 1. Abra o Curió.
> 2. Toque em uma data no calendário ou vá até a aba Notas.
> 3. Crie ou edite uma nota diária.
> 4. Toque em `Notificação`.
> 5. Se o Android solicitar autorização de alarme/lembrete, conceda a permissão
>    na tela do sistema e volte ao app.
> 6. Defina título, data e horário da notificação.
> 7. Salve. A notificação aparecerá em "Próximas notificações".
>
> A permissão é usada apenas para notificações locais criadas explicitamente
> pelo usuário.

## Roteiro do vídeo de demonstração

Duração recomendada: 45 a 90 segundos.

1. Tela inicial do Curió.
2. Abrir `Agenda` ou `Notas`.
3. Selecionar o dia atual.
4. Digitar uma nota simples, por exemplo: `Revisar documentos`.
5. Tocar em `Notificação`.
6. Mostrar a tela de autorização do Android, se aparecer.
7. Conceder `Alarmes e lembretes` ou permissão equivalente.
8. Voltar ao Curió.
9. Criar uma notificação com:
   - título: `Revisar documentos`
   - data: hoje
   - hora: alguns minutos à frente
10. Salvar.
11. Mostrar a notificação em `Próximas notificações`.
12. Abrir a notificação para mostrar que ela leva ao conteúdo do dia.

Não grave dados reais, tokens de sync, URLs privadas ou notas pessoais.

## Respostas para "Segurança dos dados"

Use estas respostas como base no formulário de Data safety.

### O app coleta dados?

Resposta curta: sim, apenas dados fornecidos pelo usuário dentro do app.

Dados:

- notas
- conteúdo de agenda
- notificações criadas pelo usuário
- configurações de sincronização, quando o usuário ativa sync

### O app compartilha dados com terceiros?

Resposta sugerida: não.

O Curió não possui anúncios, analytics, rastreamento, SDK de marketing ou nuvem
operada pelo desenvolvedor. A sincronização é opcional e vai para um servidor
configurado pelo próprio usuário.

### Os dados são enviados para fora do dispositivo?

Resposta sugerida: somente se o usuário configurar sync.

Texto:

> Por padrão, os dados ficam no dispositivo. Se o usuário configurar
> sincronização, notas e metadados de sync são enviados ao servidor escolhido
> pelo próprio usuário.

### Os dados são criptografados em trânsito?

Resposta sugerida: sim para builds de release.

Texto:

> Builds de release exigem HTTPS para sync remoto. O servidor local de testes é
> usado apenas em ambiente controlado.

### O usuário pode excluir dados?

Resposta sugerida: sim.

Texto:

> O usuário pode excluir notas e notificações no app. Se sync estiver ativo,
> marcadores de exclusão podem ser enviados ao servidor configurado pelo usuário
> para refletir a exclusão em outros dispositivos.

## Texto curto para a descrição da loja

Inclua uma frase assim na descrição pública da Play:

> Crie notas diárias e notificações locais no horário escolhido.

Também é útil incluir:

> O Curió é local-first: suas notas ficam no dispositivo, com sincronização
> opcional para servidor configurado por você.

## Antes de enviar o AAB

Verificar:

- `SCHEDULE_EXACT_ALARM` está presente.
- `USE_EXACT_ALARM` está ausente.
- `USE_FULL_SCREEN_INTENT` está ausente.
- `allowBackup=false` está presente.
- `usesCleartextTraffic=false` no release.
- `android/key.properties` existe localmente, mas não está no Git.
- O AAB foi gerado por build de release, não debug.

Comando recomendado:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\android\build-release-appbundle.ps1
```

Artefato esperado:

```text
build\app\outputs\bundle\release\app-release.aab
```

## Se a Play rejeitar a permissão

Responder com este argumento:

> A permissão `SCHEDULE_EXACT_ALARM` é usada somente para notificações locais
> criadas manualmente pelo usuário. O usuário escolhe data e hora. O app não usa
> alarmes exatos para analytics, anúncios, sync em segundo plano ou engajamento
> promocional. Sem essa permissão, o recurso principal de lembrete no horário
> escolhido não é confiável em Android 14+. O app respeita a decisão do usuário:
> se a permissão não for concedida, notas e agenda continuam funcionando.

Se a rejeição insistir que o app não é calendário/alarme, manter
`SCHEDULE_EXACT_ALARM` e não migrar para `USE_EXACT_ALARM`. A alternativa é
degradar notificações para agendamento aproximado, mas isso reduz a precisão do
recurso principal.

## Referências oficiais

Verificado em 22/05/2026:

- Política do Google Play sobre permissões e APIs sensíveis:
  https://support.google.com/googleplay/android-developer/answer/16558241
- Mudança do Android 14 para alarmes exatos:
  https://developer.android.com/about/versions/14/changes/schedule-exact-alarms
- Guia Android para agendar alarmes:
  https://developer.android.com/develop/background-work/services/alarms
