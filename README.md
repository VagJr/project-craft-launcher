# Project Craft Launcher

Launcher exclusivo para Windows x64, feito com Electron, Minecraft Launcher Core e autenticação MSMC. Identidade original do Project Craft, instalação gerenciada de Java 17/Forge, atualização do modpack, reparo, memória configurável, perfil econômico e endereço público dinâmico.

Site: https://project-craft-fps.vercel.app/#downloads
Downloads: https://github.com/VagJr/project-craft-launcher/releases
Discord: https://discord.gg/vZYuuR6KUG

## Jogadores

A distribuição anterior foi suspensa após um alerta do Windows Defender no instalador 1.0.1. A versão 1.1.0 usa MSI e ZIP e foi autorizada pelo responsável para publicação sem certificado de publicador, após verificações locais limpas. Escolha a identificação, ajuste a memória e clique em Jogar. Arquivos do Minecraft são obtidos em tempo de instalação; o instalador não contém o jogo da Mojang. O pacote é separado das outras instalações em `%APPDATA%/ProjectCraft/game`.

O modo Microsoft abre a janela de autenticação do provedor e armazena a sessão com criptografia do Windows quando disponível. O modo por nick abre o cliente com identidade local para servidores compatíveis. **O servidor principal ainda está em online-mode=true**: o modo por nick não concede acesso ao principal. A liberação exige uma migração separada de autenticação/UUIDs, com proteção das contas e dos personagens existentes. Não anuncie suporte completo ao principal por nick enquanto essa migração não estiver concluída.

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

O instalador MSI padrão do Windows e o ZIP são gerados separadamente. `npm run build:clean` usa uma pasta nova, `npm ci --ignore-scripts`, auditoria de procedência npm e checksum oficial do Electron; saídas em build/1.1.0, com hashes e proveniência. Não há certificado de publicador Windows configurado. A assinatura Ed25519 do canal valida as versões do pacote e é distinta da assinatura de publicador do Windows.

Dependências antigas do Minecraft Launcher Core foram substituídas por adm-zip 0.6.1, @cypress/request e uuid 11.1.1 através de overrides. A auditoria de dependências reportou zero vulnerabilidades após as correções. Mantenha o package-lock e teste a instalação/inicialização a cada atualização da base.

Licenças próprias de Minecraft, mods, fontes e artes continuam aplicáveis. A licença MIT da fonte do launcher não transfere direitos sobre esses componentes.

## Segurança da distribuição

Os downloads 1.0.0 e 1.0.1 foram retirados. O alerta Program:Win32/Contebrew.A!ml foi reproduzido no instalador 1.0.1; não existe confirmação de falso positivo. Não restaure nem libere a amostra bloqueada.

A atualização do launcher usa o mesmo manifesto Ed25519 verificado do pacote, exige MSI da release oficial, tamanho e SHA-256 e confere o arquivo novamente antes da abertura. A instalação é apresentada pelo Windows após confirmação do usuário. O pacote do jogo continua sendo preparado automaticamente.

`npm run release:launcher` cria somente rascunho. A opção `-- --publish` exige relatório de `scripts/inspect-release.ps1` com verificações locais limpas, MSI e aplicativo com assinatura Authenticode válida e hashes atuais. Uma publicação manual sem certificado, expressamente autorizada, usa adicionalmente `--allow-unsigned` e continua exigindo verificações locais limpas e hashes idênticos. Uma verificação local limpa não garante a reputação do SmartScreen ou o resultado em todos os antivírus. A assinatura Ed25519 do canal não identifica o publicador perante o Windows.

Para verificar a compilação no Defender, use Windows PowerShell 5.1: `scripts/inspect-release.ps1 -ReleaseDir build/1.1.0 -OutputDir .local/security`. O script faz varredura sem alterar proteções ou restaurar arquivos em quarentena.
