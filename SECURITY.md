# Segurança da distribuição

Em 25/10/2026 o Microsoft Defender identificou o instalador 1.0.1 como Program:Win32/Contebrew.A!ml. O alerta foi reproduzido localmente no arquivo cujo SHA-256 coincide com o artefato do GitHub. A distribuição 1.0.0/1.0.1 foi retirada. Não há confirmação de falso positivo; não execute nem restaure o instalador anterior.

A versão 1.1.0 foi reconstruída em uma pasta nova usando package-lock, instalação npm sem scripts automáticos, auditoria de assinaturas de procedência e SHA-256 oficial do Electron. Foram verificadas assinaturas de origem de 331 pacotes npm, 42 atestações e nenhuma vulnerabilidade conhecida na auditoria daquele momento. Esses resultados não equivalem a uma garantia de ausência de malware.

O MSI, o ZIP e a pasta completa do aplicativo passaram na verificação local do Defender em 25/10/2026: mecanismo 1.1.26100.4, plataforma 4.18.26100.4, definições 1.461.197.0. A proteção em tempo real permaneceu ativa. Os 72 arquivos extraídos do MSI coincidiram com os arquivos examinados e o aplicativo abriu e encerrou sem erro. Quatorze testes passaram; um teste de links simbólicos foi ignorado no Windows.

O responsável pelo projeto autorizou expressamente publicar a versão 1.1.0 sem certificado de publicador. O MSI e o aplicativo não têm assinatura Authenticode. O Windows pode apresentar avisos de aplicativo desconhecido; a varredura local não prevê todos os resultados de reputação, nuvem ou outros antivírus. Não é necessário desativar proteções ou criar exclusões para usar este projeto. Uma detecção deve ser investigada.

As atualizações do aplicativo exigem um manifesto Ed25519 válido, MSI hospedado na release oficial, versão superior, tamanho e SHA-256. O hash é novamente conferido antes de apresentar o instalador do Windows. A assinatura do canal é distinta de um certificado de publicador Windows.

`npm run release:launcher` cria rascunho. `-- --publish` exige assinatura válida e varreduras limpas; `-- --publish --allow-unsigned` serve para uma publicação manual expressamente autorizada sem certificado e mantém a exigência de varreduras limpas e hashes idênticos. O monitor de pacotes não publica versões do launcher.

Para contestar uma detecção, use o [portal de análise da Microsoft](https://www.microsoft.com/en-us/wdsi/filesubmission/). Consulte também a [documentação de reputação do SmartScreen](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation). Assinatura e reputação são etapas diferentes; nenhuma alegação de ausência universal de bloqueios é feita.
