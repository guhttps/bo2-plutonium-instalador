# Privacidade nas publicações

O código, a documentação e os ZIPs publicados devem usar instruções genéricas, com marcadores como `IP_DO_ANFITRIAO_NO_RADMIN` e variáveis como `%LOCALAPPDATA%`. Endereços de jogadores, redes privadas, senhas de grupo, contas e registros de sessão pertencem ao ambiente local.

A revisão realizada incluiu os cinco commits existentes até a v1.1.3, os cinco ZIPs de Releases, suas notas, os nove logs de etapas concluídas do Actions e a imagem da interface. Não foram encontrados os IPs dos participantes, caminhos de perfil pessoais ou credenciais pesquisados. A imagem usa uma pasta de exemplo e não contém metadados textuais ou EXIF. Os autores dos commits usam o endereço público `noreply` do GitHub.

## Verificações automáticas

`verificar-privacidade.ps1` procura padrões de IPv4/IPv6 reais, caminhos pessoais, emails, tokens conhecidos, chaves privadas e algumas atribuições de credenciais. Endereços de loopback, de escuta local e das faixas reservadas para documentação são permitidos para os testes. O relatório informa o arquivo e a categoria, sem imprimir o valor detectado.

Arquivos locais e de credenciais são bloqueados. Os dois binários existentes — a imagem de demonstração e os metadados originais do torrent — têm hashes aprovados no verificador. Uma nova imagem, ou uma imagem alterada, exige revisão visual e atualização explícita da aprovação.

O GitHub Actions verifica os arquivos e o histórico antes dos testes e da publicação. A geração local também verifica o conteúdo que será incluído no ZIP. A detecção de segredos e a proteção de envio do GitHub estavam ativadas na auditoria, sem alertas abertos.

## Proteger commits e envios locais

Após clonar o repositório, execute na raiz:

```powershell
git config core.hooksPath .githooks
```

Os hooks usam PowerShell. Antes do commit, examinam os arquivos efetivamente preparados no índice, mesmo que a cópia de trabalho seja diferente. Antes do push, examinam o histórico local. Essa configuração é local a cada clone e precisa ser repetida em um novo clone.

Verificação manual:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\verificar-privacidade.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\verificar-privacidade.ps1 -History
```

Para testar o verificador com dados simulados, sem publicá-los:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\verificar-privacidade.ps1
```

## Limites

Essas verificações reduzem publicações acidentais e não garantem encontrar todo dado pessoal ou segredo. Os hooks podem ser contornados ou não estar instalados em outros clones. O CI executa depois que um commit é enviado: ele bloqueia a publicação do pacote, mas não impede sozinho que o conteúdo desse commit fique público. A proteção de envio do GitHub cobre os padrões de segredo suportados pelo serviço.

Revise imagens, anexos, logs e mensagens antes de publicá-los. Quando pedir suporte, substitua dados pessoais por marcadores e envie somente o trecho necessário. Um arquivo apagado da versão atual ainda pode existir em commits antigos, cópias, caches ou downloads; veja a [orientação do GitHub sobre remoção de dados](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).

O repositório é público: o perfil do proprietário e o histórico de contribuições continuam públicos. Essas medidas também não ocultam o IP da conexão dos serviços de download ou dos participantes de uma rede de jogo; não fornecem anonimato na internet.
