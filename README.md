# Project Craft Launcher

Launcher exclusivo para Windows x64, feito com Electron, Minecraft Launcher Core e autenticação MSMC. Identidade original do Project Craft, instalação gerenciada de Java 17/Forge, atualização do modpack, reparo, memória configurável, perfil econômico e endereço público dinâmico.

Site: https://project-craft-fps.vercel.app/#downloads
Downloads: https://github.com/VagJr/project-craft-launcher/releases
Discord: https://discord.gg/vZYuuR6KUG

## Jogadores

A distribuição anterior foi suspensa após um alerta do Windows Defender no instalador 1.0.1. A versão 1.2.0 usa MSI e ZIP e foi autorizada pelo responsável para publicação sem certificado de publicador, após verificações locais limpas. Escolha a identificação, ajuste a memória e clique em Jogar. Arquivos do Minecraft são obtidos em tempo de instalação; o instalador não contém o jogo da Mojang. O pacote é separado das outras instalações em `%APPDATA%/ProjectCraft/game`.

O modo Microsoft abre a janela de autenticação do provedor, renova a sessão antes de jogar e guarda o token rotacionado com criptografia do Windows quando disponível. O pacote 0.9.3 habilita contas locais no principal: selecione Entrar por nick, use sempre o mesmo nome e cadastre sua senha na tela do jogo antes da seleção dos três personagens. Nomes Microsoft existentes continuam reservados e preservam seus UUIDs. A whitelist permanece ativa. O launcher 1.2.0 sempre abre o menu inicial; selecione INICIAR JOGO para conectar.

O launcher consulta o canal de versão ao preparar/jogar, valida assinatura Ed25519 e hashes, baixa arquivos faltantes e substitui mods gerenciados antigos. Opções pessoais selecionadas são preservadas. Backups dos arquivos substituídos ficam em `.project-craft-backups` na instância. Mods manuais não gerenciados permanecem. Cada release usa versões fechadas e aprovadas; não atualiza cada mod para o mais recente individualmente. O cliente precisa ser encerrado para atualizar.

## Publicação e endereço

`channel/stable.json` e `stable.sig` indicam o pacote aprovado. `connection.json` e `connection.sig` indicam IP e porta. A chave privada fica apenas em `.local/release-private.pem`, ignorada pelo Git. Preserve uma cópia privada segura dela para conseguir continuar assinando atualizações compatíveis com o launcher instalado.

`npm run connection` compara duas fontes públicas de IP e publica somente quando elas concordam e o IP muda. Não altera portas, roteador ou firewall e não comprova acesso de fora da rede.

`npm run watch` verifica IP e novas builds a cada cinco minutos. Publica uma nova versão somente quando há pacote estável por dois minutos, build.lock, relatório de implantação correspondente e validação de exportação aprovada. O nome da versão deve mudar. Downloads publicados são imutáveis; nunca substitua um pacote público mantendo a mesma versão.

Para publicar manualmente: `npm run release`. Os comandos de operação pressupõem esta pasta dentro da estrutura local do projeto (diretório pai contém build.lock.json, dist e docs), Node e GitHub CLI autenticado. Apenas o launcher e seu conteúdo público ficam neste repositório. Dados de jogadores, tokens do Discord, conta Microsoft e mundos não são enviados.

`LIGAR-ATUALIZADOR.ps1` inicia o monitor em segundo plano. `INICIAR-SERVICOS.ps1` inicia monitor e bot. `scripts/startup.ps1` registra a inicialização ao login do Windows, sem privilégios administrativos. O bot edita uma publicação fixada com os downloads e o endereço atuais; mudanças de pacote também geram uma nota no canal de atualizações. O site consulta o mesmo canal público a cada dois minutos enquanto aberto. O .mrpack contém o IP conhecido na publicação; se ele mudar depois da importação, consulte o endereço atual no site ou no Discord.

Não há monitoramento remoto quando este computador estiver desligado. Publicações do GitHub, site e mensagens existentes continuam disponíveis. O servidor Minecraft, o atualizador e o bot dependem desta máquina.

## Desenvolvimento

Node 22 ou superior. `npm ci`, `npm test`, `npm start`, `npm run build`.

O instalador MSI padrão do Windows e o ZIP são gerados separadamente. `npm run build:clean` usa uma pasta nova, `npm ci --ignore-scripts`, auditoria de procedência npm e checksum oficial do Electron; saídas em build/1.2.0, com hashes e proveniência. Não há certificado de publicador Windows configurado. A assinatura Ed25519 do canal valida as versões do pacote e é distinta da assinatura de publicador do Windows.

Dependências antigas do Minecraft Launcher Core foram substituídas por adm-zip 0.6.1, @cypress/request e uuid 11.1.1 através de overrides. A auditoria de dependências reportou zero vulnerabilidades após as correções. Mantenha o package-lock e teste a instalação/inicialização a cada atualização da base.

Licenças próprias de Minecraft, mods, fontes e artes continuam aplicáveis. A licença MIT da fonte do launcher não transfere direitos sobre esses componentes.

## Segurança da distribuição

Os downloads 1.0.0 e 1.0.1 foram retirados. O alerta Program:Win32/Contebrew.A!ml foi reproduzido no instalador 1.0.1; não existe confirmação de falso positivo. Não restaure nem libere a amostra bloqueada.

A partir de 1.2.0, o launcher se atualiza automaticamente. Ele consulta o canal cinco segundos após abrir, a cada dez minutos e antes de jogar. O download ocorre em segundo plano. A aplicação aguarda o jogo, a preparação e a edição das configurações terminarem; o launcher encerra, instala a versão aprovada e reabre sozinho. Não há botão obrigatório de instalação. As versões 1.1.x precisam de uma única atualização para 1.2.0 para receber esse comportamento.

A atualização usa o manifesto Ed25519 já verificado, endereços oficiais, tamanho e SHA-256. O canal é consultado novamente antes da aplicação, para impedir instalar uma versão retirada. O helper Windows confere o arquivo novamente, mantém o pacote bloqueado contra alteração e espera o processo antigo encerrar. Não encerra o Minecraft nem reinicia o Windows.

Na instalação MSI, usa Windows Installer em modo silencioso, preservando a pasta de instalação. Na edição portátil ZIP, prepara os arquivos em pasta separada, preserva arquivos pessoais não gerenciados, mantém backup dos arquivos substituídos e restaura em caso de falha. Preferências, contas e jogo ficam fora dos arquivos trocados. Falhas deixam a versão atual disponível e suspendem tentativas automáticas por uma hora, evitando ciclos de reinicialização. O Windows ou políticas da máquina ainda podem exigir autorização/bloquear a instalação; proteções não são desativadas.

Referência do fluxo MSI: [opções oficiais do Windows Installer](https://learn.microsoft.com/en-us/windows/win32/msi/standard-installer-command-line-options). O helper é necessário porque o [atualizador integrado do Electron](https://www.electronjs.org/docs/latest/api/auto-updater/) não cobre esta distribuição MSI/ZIP. O pacote de mods continua sendo atualizado ao preparar/jogar.

`npm run release:launcher` cria somente rascunho. A opção `-- --publish` exige relatório de `scripts/inspect-release.ps1` com verificações locais limpas, MSI e aplicativo com assinatura Authenticode válida e hashes atuais. Uma publicação manual sem certificado, expressamente autorizada, usa adicionalmente `--allow-unsigned` e continua exigindo verificações locais limpas e hashes idênticos. Uma verificação local limpa não garante a reputação do SmartScreen ou o resultado em todos os antivírus. A assinatura Ed25519 do canal não identifica o publicador perante o Windows.

Para verificar a compilação no Defender, use Windows PowerShell 5.1: `scripts/inspect-release.ps1 -ReleaseDir build/1.2.0 -OutputDir .local/security`. O script faz varredura sem alterar proteções ou restaurar arquivos em quarentena.
