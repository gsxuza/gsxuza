# Cria o GitHub Project "Kanban dos projetos" com as colunas
# Backlog | Em andamento | Em revisão | Concluídas e coloca cada tarefa na coluna certa.
#
# Precisa do GitHub CLI (gh) logado na conta gsxuza com permissão de projects:
#   gh auth login -h github.com -s project -w
#
# Como rodar (PowerShell):
#   powershell -ExecutionPolicy Bypass -File .\criar-project.ps1

$ErrorActionPreference = 'Continue'
$utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$env:GH_NO_UPDATE_NOTIFIER = '1'
$env:GH_PROMPT_DISABLED = '1'

$Owner = 'gsxuza'
$Title = 'Kanban dos projetos'
$Projetos = 'Scanner Peugeot 2008,Psicologia Acolhedora,ATLAS,Jogo do Tatu,Prospecção de Clientes,Finance Time,Rose Artesanatos,Ecos de Brumafria,Bot Validação Pix,Medley Bot,Solo Desk,Controle de Consumíveis,Coração Lar e Propósito,LifeOS RPG,PizzariaFlow,BarberFlow Elite,Portfólios e perfil'
$Repos = 'gsxuza/Controle-consumiveis- gsxuza/bot-validacao-pix gsxuza/ecos-de-brufumaria gsxuza/finance-time gsxuza/gsxuza gsxuza/jogo-do-tatu gsxuza/prospec-o-clientes gsxuza/psicologia-acolhedora gsxuza/rose-artesanatos-sistema gsxuza/sistema-operacional-Rose-Artesanatos-v2' -split ' '
$Total = 95
$ErrFile = [System.IO.Path]::GetTempFileName()
$GqlFile = [System.IO.Path]::GetTempFileName()

function Fail([string]$Msg) {
    Write-Host "ERRO: $Msg" -ForegroundColor Red
    Remove-Item $ErrFile, $GqlFile -ErrorAction SilentlyContinue
    exit 1
}

# Roda o gh com a lista de argumentos e devolve o texto da saída. Para o script se der erro.
function Invoke-Gh([string[]]$A) {
    $out = & gh @A 2> $ErrFile
    if ($LASTEXITCODE -ne 0) {
        $err = Get-Content $ErrFile -Raw -ErrorAction SilentlyContinue
        Fail ('gh ' + ($A -join ' ') + ' falhou: ' + $err)
    }
    return ($out -join "`n")
}

function Invoke-GhJson([string[]]$A) {
    $text = Invoke-Gh $A
    if (-not $text) { Fail ('resposta vazia de: gh ' + ($A -join ' ')) }
    return ($text | ConvertFrom-Json)
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail 'GitHub CLI (gh) não encontrado.' }

$login = (Invoke-GhJson @('api', 'user')).login
if ($login -ne $Owner) { Fail "o gh está usando a conta '$login', não a $Owner. Rode: gh auth switch -u $Owner" }

$list = Invoke-GhJson @('project', 'list', '--owner', $Owner, '--limit', '200', '--format', 'json')
if ($list.projects | Where-Object { $_.title -eq $Title }) {
    Fail "já existe um project chamado '$Title'. Apague ou renomeie esse antes de rodar de novo."
}

Write-Host '1/4 Criando o project...'
$proj = Invoke-GhJson @('project', 'create', '--owner', $Owner, '--title', $Title, '--format', 'json')
$Num = [string]$proj.number
$ProjId = [string]$proj.id
$Url = [string]$proj.url
if (-not $Num -or -not $ProjId) { Fail 'não consegui criar o project' }
& gh @('project', 'edit', $Num, '--owner', $Owner, '--description', 'Backlog, em andamento, em revisão e concluídas de todos os repositórios') 2> $ErrFile | Out-Null

function Get-Fields { return (Invoke-GhJson @('project', 'field-list', $Num, '--owner', $Owner, '--limit', '50', '--format', 'json')).fields }
function Find-Field($Fields, [string]$Name) { return ($Fields | Where-Object { $_.name -eq $Name } | Select-Object -First 1) }

Write-Host '2/4 Configurando as colunas e o campo Projeto...'
$fields = Get-Fields
$StatusName = 'Status'
$status0 = Find-Field $fields 'Status'
$gql = @{
    query     = 'mutation($id: ID!) { updateProjectV2Field(input: {fieldId: $id, singleSelectOptions: [' +
                '{name: "Backlog", color: GREEN, description: "Ainda não começou"}, ' +
                '{name: "Em andamento", color: YELLOW, description: "Sendo feito agora"}, ' +
                '{name: "Em revisão", color: BLUE, description: "Pronto numa branch, esperando revisão ou merge"}, ' +
                '{name: "Concluídas", color: PURPLE, description: "Entregue"}' +
                ']}) { clientMutationId } }'
    variables = @{ id = [string]$status0.id }
} | ConvertTo-Json -Depth 5 -Compress
[System.IO.File]::WriteAllText($GqlFile, $gql, $utf8)
& gh @('api', 'graphql', '--method', 'POST', '--input', $GqlFile) 2> $ErrFile | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host '   Não deu para renomear as colunas do Status; usando um campo "Coluna".'
    $StatusName = 'Coluna'
    Invoke-Gh @('project', 'field-create', $Num, '--owner', $Owner, '--name', 'Coluna', '--data-type', 'SINGLE_SELECT',
                '--single-select-options', 'Backlog,Em andamento,Em revisão,Concluídas') | Out-Null
}
Invoke-Gh @('project', 'field-create', $Num, '--owner', $Owner, '--name', 'Projeto', '--data-type', 'SINGLE_SELECT',
            '--single-select-options', $Projetos) | Out-Null
$fields = Get-Fields
$StatusField = Find-Field $fields $StatusName
$ProjField = Find-Field $fields 'Projeto'
if (-not $StatusField -or -not $ProjField) { Fail 'campos do project não encontrados' }

function Set-Option([string]$ItemId, $Field, [string]$Value) {
    $opt = $Field.options | Where-Object { $_.name -eq $Value } | Select-Object -First 1
    if (-not $opt) { Fail ("opção '" + $Value + "' não existe no campo " + $Field.name) }
    Invoke-Gh @('project', 'item-edit', '--id', $ItemId, '--project-id', $ProjId, '--field-id', [string]$Field.id,
                '--single-select-option-id', [string]$opt.id) | Out-Null
}

Write-Host "3/4 Adicionando $Total cartões (leva alguns minutos)..."
$Dados = @'
I	Em revisão	Scanner Peugeot 2008	https://github.com/gsxuza/gsxuza/issues/1	
I	Em revisão	Scanner Peugeot 2008	https://github.com/gsxuza/gsxuza/issues/2	
I	Em revisão	Jogo do Tatu	https://github.com/gsxuza/jogo-do-tatu/issues/2	
I	Em revisão	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/18	
I	Em andamento	Scanner Peugeot 2008	https://github.com/gsxuza/gsxuza/issues/3	
I	Em andamento	ATLAS	https://github.com/gsxuza/gsxuza/issues/4	
I	Em andamento	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/19	
I	Backlog	Controle de Consumíveis	https://github.com/gsxuza/Controle-consumiveis-/issues/1	
I	Backlog	Bot Validação Pix	https://github.com/gsxuza/bot-validacao-pix/issues/1	
I	Backlog	Ecos de Brumafria	https://github.com/gsxuza/ecos-de-brufumaria/issues/1	
I	Backlog	Ecos de Brumafria	https://github.com/gsxuza/ecos-de-brufumaria/issues/2	
I	Backlog	Ecos de Brumafria	https://github.com/gsxuza/ecos-de-brufumaria/issues/3	
I	Backlog	Ecos de Brumafria	https://github.com/gsxuza/ecos-de-brufumaria/issues/4	
I	Backlog	Ecos de Brumafria	https://github.com/gsxuza/ecos-de-brufumaria/issues/5	
I	Backlog	Ecos de Brumafria	https://github.com/gsxuza/ecos-de-brufumaria/issues/6	
I	Backlog	Finance Time	https://github.com/gsxuza/finance-time/issues/1	
I	Backlog	Scanner Peugeot 2008	https://github.com/gsxuza/gsxuza/issues/5	
I	Backlog	Scanner Peugeot 2008	https://github.com/gsxuza/gsxuza/issues/6	
I	Backlog	Scanner Peugeot 2008	https://github.com/gsxuza/gsxuza/issues/7	
I	Backlog	Scanner Peugeot 2008	https://github.com/gsxuza/gsxuza/issues/8	
I	Backlog	Scanner Peugeot 2008	https://github.com/gsxuza/gsxuza/issues/9	
I	Backlog	Scanner Peugeot 2008	https://github.com/gsxuza/gsxuza/issues/10	
I	Backlog	Scanner Peugeot 2008	https://github.com/gsxuza/gsxuza/issues/11	
I	Backlog	Prospecção de Clientes	https://github.com/gsxuza/prospec-o-clientes/issues/2	
I	Backlog	Prospecção de Clientes	https://github.com/gsxuza/prospec-o-clientes/issues/3	
I	Backlog	Prospecção de Clientes	https://github.com/gsxuza/prospec-o-clientes/issues/4	
I	Backlog	Prospecção de Clientes	https://github.com/gsxuza/prospec-o-clientes/issues/5	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/20	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/21	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/22	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/23	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/24	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/25	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/26	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/27	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/28	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/29	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/30	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/31	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/32	
I	Backlog	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/issues/33	
I	Backlog	Rose Artesanatos	https://github.com/gsxuza/rose-artesanatos-sistema/issues/1	
I	Backlog	Rose Artesanatos	https://github.com/gsxuza/sistema-operacional-Rose-Artesanatos-v2/issues/1	
D	Concluídas	Scanner Peugeot 2008	Scanner: Android Auto ao ligar não retoma a rádio do multimídia	Versão 0.1.175 (23/11). https://github.com/szadil763/Scanner-virtual-peugeut-2008
D	Concluídas	Scanner Peugeot 2008	Scanner: Registro de erros com envio pelo WhatsApp	O motivo do fechamento aparece na abertura seguinte (21/11). https://github.com/szadil763/Scanner-virtual-peugeut-2008
D	Concluídas	Scanner Peugeot 2008	Scanner: Versão de transição da chave de assinatura	PR #6 (20/11): https://github.com/szadil763/Scanner-virtual-peugeut-2008/pull/6
D	Concluídas	Scanner Peugeot 2008	Scanner: Gráficos da Saúde voltam a aparecer no painel	PR #5 (20/11): https://github.com/szadil763/Scanner-virtual-peugeut-2008/pull/5
D	Concluídas	Scanner Peugeot 2008	Scanner: Fase 1: resiliência do painel e da nuvem	PR #4 (19/11): https://github.com/szadil763/Scanner-virtual-peugeut-2008/pull/4 (o PR #3 foi fechado, substituído pelo #4)
D	Concluídas	Medley Bot	Medley Bot: v0 do bot de medleys para dança	Telegram + Claude ou Gemini, letra com horários, contagem de 8, transições, separação de voz (Demucs), Docker e atalho para Windows (19/11). https://github.com/gsxuza/medley-bot
D	Concluídas	Scanner Peugeot 2008	Scanner: Painel do multimídia e Android Auto sem fio	Abas Combustível, Manutenção e Mapa; dados do celular pelo Wi-Fi do multimídia. https://github.com/szadil763/Scanner-virtual-peugeut-2008
D	Concluídas	Coração Lar e Propósito	Coração Lar e Propósito: Site com área administrativa no Base44	Eventos, clube do livro, mentoria, posts, parcerias e depoimentos (atualizado em 13/11). https://github.com/gsxuza/coracao-lar-proposito
D	Concluídas	Scanner Peugeot 2008	Scanner: Identificação do carro pelo chassi (VIN)	PR #1 (11/11): https://github.com/szadil763/Scanner-virtual-peugeut-2008/pull/1
D	Concluídas	Scanner Peugeot 2008	Scanner: Nuvem: dados do carro sincronizados entre celulares	Abastecimentos, manutenção, postos, tanque, trajeto e Saúde seguem o carro. https://github.com/szadil763/Scanner-virtual-peugeut-2008
D	Concluídas	Scanner Peugeot 2008	Scanner: Aba Postos com ranking por rendimento do combustível	https://github.com/szadil763/Scanner-virtual-peugeut-2008
D	Concluídas	Scanner Peugeot 2008	Scanner: Comando de voz	Perguntas, pedidos, rota, rádio e música. https://github.com/szadil763/Scanner-virtual-peugeut-2008
D	Concluídas	Ecos de Brumafria	Ecos de Brumafria: RPG com toda a regra no PostgreSQL	Console e interface web (05/11). https://github.com/gsxuza/ecos-de-brufumaria
D	Concluídas	Scanner Peugeot 2008	Scanner: Troca de óleo e leitura de falhas (modos 03 e 07)	https://github.com/szadil763/Scanner-virtual-peugeut-2008
D	Concluídas	Scanner Peugeot 2008	Scanner: Saúde do carro com gráficos e antes/depois do abastecimento	https://github.com/szadil763/Scanner-virtual-peugeut-2008
D	Concluídas	Scanner Peugeot 2008	Scanner: Leitura real pelo ELM327 e consumo calibrado	BLE e Bluetooth clássico; consumo por PID 5E, MAF ou MAP com calibração por abastecimentos. https://github.com/szadil763/Scanner-virtual-peugeut-2008
D	Concluídas	Scanner Peugeot 2008	Scanner: Fase 0: protótipo, fórmulas OBD e esqueleto Android	https://github.com/szadil763/Scanner-virtual-peugeut-2008
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/17	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/16	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/15	
D	Concluídas	Portfólios e perfil	Portfólios e perfil: README do perfil atualizado	12/10. https://github.com/gsxuza/gsxuza
D	Concluídas	LifeOS RPG	LifeOS RPG: App no Base44	Dashboard, pessoal, profissional (com kanban), finanças e onboarding. https://github.com/gsxuza/lifeos-rpg-do-desenvolvimento
D	Concluídas	Solo Desk	Solo Desk: Saída do Base44 para Vite + Supabase na Vercel	Com módulos de Parafusos e Ferramentas. https://github.com/gsxuza/invent-rio-solo
D	Concluídas	Finance Time	Finance Time: Exportação de transações em CSV	08/09, na branch main. https://github.com/gsxuza/finance-time
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/14	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/13	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/12	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/11	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/10	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/9	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/8	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/7	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/6	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/5	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/4	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/3	
D	Concluídas	Finance Time	Finance Time: Botão para ocultar os valores	31/08, na branch main. https://github.com/gsxuza/finance-time
I	Concluídas	Prospecção de Clientes	https://github.com/gsxuza/prospec-o-clientes/pull/1	
D	Concluídas	Rose Artesanatos	Rose Artesanatos: Importação deixa de perder pedidos	26/08. https://github.com/gsxuza/rose-artesanatos-sistema
D	Concluídas	Finance Time	Finance Time: Metas, fluxo de caixa, score de saúde e notificações	25/08. https://github.com/gsxuza/finance-time
D	Concluídas	Finance Time	Finance Time: Open Finance pela Pluggy	Contas, faturas e categorias. https://github.com/gsxuza/finance-time
D	Concluídas	Rose Artesanatos	Rose Artesanatos: Acompanhamento de pedidos cancelados no Mercado Livre	Com testes de ponta a ponta (22/08). https://github.com/gsxuza/rose-artesanatos-sistema
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/2	
I	Concluídas	Psicologia Acolhedora	https://github.com/gsxuza/psicologia-acolhedora/pull/1	
I	Concluídas	Jogo do Tatu	https://github.com/gsxuza/jogo-do-tatu/pull/1	
D	Concluídas	Jogo do Tatu	Jogo do Tatu: Redesign visual e tela cheia	05/08. https://github.com/gsxuza/jogo-do-tatu
D	Concluídas	Rose Artesanatos	Rose Artesanatos: Login, pedidos por data e impressão da lista	22/07 a 23/07. https://github.com/gsxuza/rose-artesanatos-sistema
D	Concluídas	Rose Artesanatos	Rose Artesanatos: Migração para Vercel Functions + Supabase	Estado multiusuário (15/07 a 22/07). https://github.com/gsxuza/rose-artesanatos-sistema
D	Concluídas	PizzariaFlow	PizzariaFlow: App no Base44	Cardápio, checkout, cozinha, entregador, rastreio e administração. https://github.com/gsxuza/pizzariaflow
D	Concluídas	Portfólios e perfil	Portfólios e perfil: Portfólios comercial e técnico	gsxuza.github.io e dev (28/06). https://github.com/gsxuza/gsxuza.github.io
D	Concluídas	BarberFlow Elite	BarberFlow Elite: App no Base44	Agenda, recepção, clientes, comissões, caixa, fidelidade e relatórios. https://github.com/gsxuza/barberflow-elite
D	Concluídas	Rose Artesanatos	Rose Artesanatos: Sistema completo	Dashboard, pedidos, financeiro, estoque, despacho e equipe (10/06). https://github.com/gsxuza/rose-artesanatos-sistema
'@
$n = 0
foreach ($line in ($Dados -split "`r?`n")) {
    if (-not $line.Trim()) { continue }
    $p = $line -split "`t"
    $n++
    if ($p[0] -eq 'I') {
        $item = (Invoke-GhJson @('project', 'item-add', $Num, '--owner', $Owner, '--url', $p[3], '--format', 'json')).id
    } else {
        $item = (Invoke-GhJson @('project', 'item-create', $Num, '--owner', $Owner, '--title', $p[3], '--body', $p[4], '--format', 'json')).id
    }
    if (-not $item) { Fail ('não consegui adicionar: ' + $p[3]) }
    Set-Option $item $StatusField $p[1]
    Set-Option $item $ProjField $p[2]
    Write-Host ('   {0,3}/{1}  {2,-13} {3}' -f $n, $Total, $p[1], $p[3])
}

Write-Host '4/4 Ligando o project aos repositórios...'
foreach ($r in $Repos) {
    & gh @('project', 'link', $Num, '--owner', $Owner, '--repo', $r) 2> $ErrFile | Out-Null
}
Remove-Item $ErrFile, $GqlFile -ErrorAction SilentlyContinue

Write-Host ''
Write-Host "Pronto: $Url" -ForegroundColor Green
Write-Host ''
Write-Host 'Falta só deixar a visualização como quadro (3 cliques):'
Write-Host '  1. Abra o link acima, clique na setinha da aba "View 1" > Layout > Board.'
Write-Host '  2. Na mesma setinha, Rename > "Kanban".'
Write-Host '  3. Em View (canto direito) > Fields, marque "Projeto" e "Labels" para aparecerem nos cartões.'
if ($StatusName -eq 'Coluna') { Write-Host '  4. Em View > Column by, escolha "Coluna".' }
Write-Host ''
Write-Host 'Em Workflows (canto superior direito), confira "Item closed" e "Pull request merged":'
Write-Host 'eles devem mover o cartão para "Concluídas".'
