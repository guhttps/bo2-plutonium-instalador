# Instalador BO2 + Plutonium para Windows

[![Verificar e publicar ZIP](https://github.com/guhttps/bo2-plutonium-instalador/actions/workflows/pacote.yml/badge.svg)](https://github.com/guhttps/bo2-plutonium-instalador/actions/workflows/pacote.yml)

Instalador com interface para Windows que baixa e prepara **Black Ops II Multiplayer, Zombies e DLCs** com o Plutonium. Escolha a pasta e acompanhe o progresso geral, a velocidade e o tempo estimado na janela. O jogo tem **14,54 GB**; o ZIP do assistente tem aproximadamente **1,1 MB** e faz o download durante a instalação.

![Janela do instalador, com seleção de pasta e progresso geral](docs/interface.png)

## Baixar e instalar

**[Baixar BO2-Plutonium.zip](https://github.com/guhttps/bo2-plutonium-instalador/releases/latest/download/BO2-Plutonium.zip)**

1. Baixe o ZIP pelo link acima e extraia todos os arquivos.
2. Abra `INSTALAR.cmd` com dois cliques.
3. Na janela, clique em **Escolher pasta** ou digite o destino. Clique em **Instalar agora**.
4. Acompanhe o download e a verificação. Se o Windows pedir autorização para instalar componentes Microsoft ausentes, confirme essa etapa.
5. Ao concluir, clique em **Abrir Plutonium**. Entre com sua própria conta ou [crie uma conta](https://forum.plutonium.pw/register).
6. Escolha **Black Ops 2 Multiplayer** ou **Zombies** e clique em **PLAY**.

O instalador configura a pasta do jogo e cria um atalho na área de trabalho.

### Se aparecer que `instalar.ps1` não existe

Feche o assistente. Clique com o botão direito em `BO2-Plutonium.zip` e escolha **Extrair Tudo…**. Abra a pasta extraída e execute `INSTALAR.cmd` de lá. Abrir o instalador diretamente dentro do ZIP pode disponibilizar apenas parte dos arquivos em uma pasta temporária.

O pacote completo contém 13 arquivos. A abertura verifica os arquivos necessários e orienta a extração se faltar algum. Se já extraiu tudo e o aviso continuar, baixe novamente o ZIP completo pelo link acima e extraia em uma nova pasta.

## Requisitos

- Windows 10 ou 11 de 64 bits.
- Placa de vídeo compatível com DirectX 11.
- Internet e pelo menos **18 GB livres** no disco do jogo.
- Reserve também **1 GB livre em C:** para o cliente e os componentes.

A campanha não faz parte deste pacote.

## Jogar Zombies com amigos pelo Radmin VPN

Este foi o caminho confirmado pelo usuário para jogar com amigos em PCs diferentes: **Radmin VPN + Play in LAN mode + CUSTOM GAMES + conexão direta pela porta 4976**. O Radmin cria uma rede virtual entre os participantes, mesmo em casas diferentes. A configuração dessa rede é feita separadamente da instalação do jogo.

### Preparar os PCs

1. Todos instalam e abrem o [Radmin VPN oficial](https://www.radmin-vpn.com/help/index.html).
2. Quem vai hospedar cria uma rede com nome e senha. Os amigos entram **nessa mesma rede** pelo Radmin e conferem se os participantes aparecem online.
3. Se o adaptador do Radmin estiver desativado, use **Win + R → `ncpa.cpl` → botão direito em Radmin VPN → Ativar**.
4. Com o Radmin conectado, todos fecham o BO2 e abrem **Black Ops II Zombies** no launcher pela seta ao lado de Play → **Play in LAN mode**. Essa opção desativa o anticheat, conforme o aviso do launcher.

O modo LAN sozinho atende à rede local. Para PCs em casas diferentes, este procedimento usa a rede virtual compartilhada do Radmin. Veja as [instruções do Radmin](https://www.radmin-vpn.com/help/index.html) e a [conexão por IP no Plutonium](https://plutonium.pw/docs/custom-games/#connecting-via-an-ip-address).

### Hospedar e conectar

1. O anfitrião entra em **CUSTOM GAMES**, escolhe o mapa e inicia a partida.
2. Aguarda o personagem aparecer no mapa e mantém a partida **despausada** enquanto os amigos conectam.
3. Os amigos abrem o console do BO2 e executam o comando abaixo, substituindo `IP_DO_ANFITRIAO_NO_RADMIN` pelo endereço **26.x.x.x exibido ao lado do PC de quem hospeda no Radmin**:

   ```text
   connect IP_DO_ANFITRIAO_NO_RADMIN:4976
   ```

Use o IP do anfitrião. No teste confirmado, a conexão direta em LAN funcionou pela **UDP 4976**. A porta **3074** aparece nas instruções dos convites online do T6; são procedimentos diferentes. Se a porta do jogo tiver sido alterada, o anfitrião pode consultar `net_port` no console e informar o valor correto aos amigos.

### Entrou como espectador?

Quem entra com uma rodada já em andamento pode ficar como espectador até a próxima. **Os amigos permanecem conectados, e o anfitrião termina a rodada eliminando os zumbis restantes.** Se entraram no round 1, devem aparecer para jogar no início do round 2. Esse comportamento também foi confirmado pelo usuário e está descrito no [fórum do Plutonium](https://forum.plutonium.pw/topic/10836/hosting-joining-zombies-custom-games/3).

### Se a conexão falhar

- **Só aparece “Attempting to connect”:** confira o IP do anfitrião no Radmin, a porta indicada por `net_port`, a mesma rede do Radmin em todos os PCs, o modo LAN e a partida de CUSTOM GAMES já iniciada e despausada.
- **“Unable to join game session” nos convites online:** o aviso pode envolver firewall, escolha de adaptador ou roteador. Em conexões com CGNAT, encaminhar uma porta apenas no roteador doméstico pode não bastar; a conexão via Radmin foi a alternativa testada neste caso. O [guia de convites do T6](https://plutonium.pw/docs/custom-games/#t6) descreve o procedimento online normal.
- **O jogo mostra o IP de uma rede virtual sem uso:** compare **OPTIONS → SYSTEM INFO → INTERNAL** com os endereços exibidos por `ipconfig`. No PC utilizado houve seleção de adaptadores do VirtualBox e Hyper-V. Para investigar esse caso, feche o jogo, desative temporariamente apenas adaptadores virtuais que você não esteja usando e reabra o jogo. Mantenha ativos a conexão Ethernet/Wi-Fi usada para internet e o Radmin usado pelo grupo. Reative os adaptadores quando precisar dos respectivos programas.
- **A partida pausa enquanto só o anfitrião está jogando:** essa observação isolada não confirma uma falha de rede. Faça o teste de entrada com a partida despausada.

Permita o executável `%LOCALAPPDATA%\Plutonium\bin\plutonium-bootstrapper-win32.exe` no firewall para o perfil de rede utilizado. A [ajuda do Radmin](https://www.radmin-vpn.com/help/index.html) também explica como testar a comunicação entre participantes pelo comando Ping do aplicativo.

## Se o download for interrompido

Na janela, **Interromper** salva o andamento do download. Use **Continuar instalação** ou abra `INSTALAR.cmd` novamente, selecione a **mesma pasta** e inicie a instalação. Os arquivos completos são conferidos e reaproveitados, e as transferências com controle `.aria2` são retomadas. Mantenha esses arquivos de controle enquanto o download estiver incompleto.

A interrupção fica indisponível durante a instalação de componentes e a atualização do cliente. Nessas etapas, aguarde a conclusão. **Detalhes da instalação** mostra o registro do processo se houver um problema.

Se a fonte HTTP estiver indisponível, `ALTERNATIVA-TORRENT.cmd` usa o torrent original. Essa alternativa depende dos participantes da rede BitTorrent e compartilha dados durante o download, com limite de envio de 128 KiB/s; o compartilhamento termina ao concluir.

## Como funciona

O assistente baixa os **525 arquivos** e confere seus hashes. Depois verifica todos os **55.469 blocos** contra o torrent original, prepara os componentes Microsoft ausentes, atualiza o cliente oficial e configura `t6Path`, com backup de uma configuração existente.

O percentual do download soma os bytes de todas as transferências; arquivos já concluídos também entram no total. A verificação tem seu próprio progresso. O tempo restante é uma estimativa baseada na velocidade atual.

O launcher é baixado do fornecedor. Os arquivos do jogo vêm de um arquivo histórico do antigo pacote T6. A origem, os endereços e os hashes estão em [FONTES.txt](BO2-Plutonium/FONTES.txt).

O código do assistente está neste repositório; os dados do jogo são baixados durante a instalação. Este projeto é independente da equipe do Plutonium.

## Pasta de instalação

O jogo fica em:

```text
%USERPROFILE%\Games\BO2-Plutonium\pluto_t6_full_game
```

O assistente guarda o launcher, o cache e os registros em `%LOCALAPPDATA%\BO2-Plutonium-Assistente`. O cliente utiliza `%LOCALAPPDATA%\Plutonium`.

Para usar outro disco, abra o PowerShell na pasta extraída do assistente e execute:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\instalar.ps1 -PastaJogos "D:\Jogos\BO2-Plutonium"
```

## Validação

Foram verificados o download completo, a integridade de todos os blocos, o fluxo de instalação, a retomada de uma transferência interrompida, o reparo de um arquivo corrompido e a inicialização de Multiplayer e Zombies em LAN com Plutonium r5369.

**O usuário confirmou o funcionamento de uma partida de Zombies com amigos via Radmin VPN, modo LAN e conexão direta pela UDP 4976**, incluindo a entrada dos espectadores na rodada seguinte. Esse é um teste manual relatado pelo usuário. Os convites online normais apresentaram falhas de conexão; a validação via Radmin não confirma o funcionamento de servidores públicos, de todos os mapas ou de todas as redes.

Cada pessoa faz login no launcher com sua própria conta. A instalação de componentes Microsoft em um Windows limpo também não foi exercitada, pois eles já estavam presentes no PC utilizado.

Confira o [relatório de validação](BO2-Plutonium/VALIDACAO.txt) e as [instruções completas](BO2-Plutonium/LEIA-ME.txt).

Para executar as verificações locais do código, na raiz do repositório:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\verificar-pacote.ps1
```

Essas verificações usam pequenos arquivos temporários e não executam o jogo.

Para verificar a interface e o acompanhamento do download:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\verificar-interface.ps1 -Download
```

Esse teste usa um servidor HTTP local com arquivos pequenos, interrompe e retoma a transferência e confere os hashes. Ele baixa apenas o aria2 do projeto oficial caso o programa ainda não esteja no cache; os 14,54 GB do jogo não são baixados pelo teste.

## ZIP e versões automáticas

A cada atualização enviada para `main` e em cada pull request, o [GitHub Actions](https://github.com/guhttps/bo2-plutonium-instalador/actions/workflows/pacote.yml) executa o processo em um Windows separado:

1. Confere os arquivos obrigatórios e os hashes dos metadados originais.
2. Gera `BO2-Plutonium.zip`, extrai e compara todos os arquivos por SHA-256.
3. Testa o conteúdo extraído: verificador de integridade, configuração, janela, progresso, download, interrupção e retomada.
4. Disponibiliza o ZIP aprovado e `BO2-Plutonium.zip.sha256` em **Artifacts**, na página da execução, por 30 dias. É necessário entrar no GitHub para baixar esses artefatos.

Se qualquer verificação falhar, o fluxo falha e não publica uma nova versão. Os testes automáticos usam arquivos pequenos; não baixam o jogo nem validam partidas online.

Para publicar uma versão estável, envie as alterações e uma **nova tag** no formato `vMAJOR.MINOR.PATCH`:

```powershell
git push origin main
git tag v1.2.0
git push origin v1.2.0
```

Escolha um número ainda não utilizado. O fluxo da tag repete os testes e publica **o mesmo ZIP aprovado**, com seu checksum, em [Releases](https://github.com/guhttps/bo2-plutonium-instalador/releases). Ao final, baixa o arquivo publicado e confere o hash novamente. O link **Baixar BO2-Plutonium.zip** deste README passa a apontar para a nova versão automaticamente. Versões já publicadas não são sobrescritas.

Também é possível executar a geração pela opção **Run workflow** na aba Actions, sem publicar uma versão. O fluxo usa o token temporário do próprio GitHub; não precisa cadastrar senha ou token pessoal nos secrets.

Para gerar e testar o mesmo pacote localmente:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\criar-pacote.ps1
```

Os arquivos aprovados ficam em `dist`. Para conferir um ZIP baixado, coloque o ZIP e o arquivo `.sha256` na mesma pasta e execute nela:

```powershell
$esperado = ((Get-Content .\BO2-Plutonium.zip.sha256 -Raw).Trim() -split '\s+')[0]
if ((Get-FileHash .\BO2-Plutonium.zip -Algorithm SHA256).Hash -ine $esperado) {
    throw 'O ZIP não corresponde ao checksum publicado.'
}
'Checksum confere.'
```
