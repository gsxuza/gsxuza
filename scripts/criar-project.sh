#!/usr/bin/env bash
# Cria o GitHub Project "Kanban dos projetos" com as colunas
# Backlog | Em andamento | Em revisão | Concluídas e coloca cada tarefa na coluna certa.
#
# Precisa do GitHub CLI (https://cli.github.com) logado na conta gsxuza
# com permissão de projects. Antes de rodar, uma vez só:
#   gh auth login
#   gh auth refresh -s project
#
# No Windows, rode no Git Bash.

set -euo pipefail

OWNER="gsxuza"
TITLE="Kanban dos projetos"
PROJETOS="Scanner Peugeot 2008,Psicologia Acolhedora,ATLAS,Jogo do Tatu,Prospecção de Clientes,Finance Time,Rose Artesanatos,Ecos de Brumafria,Bot Validação Pix,Medley Bot,Solo Desk,Controle de Consumíveis,Coração Lar e Propósito,LifeOS RPG,PizzariaFlow,BarberFlow Elite,Portfólios e perfil"
REPOS="gsxuza/Controle-consumiveis- gsxuza/bot-validacao-pix gsxuza/ecos-de-brufumaria gsxuza/finance-time gsxuza/gsxuza gsxuza/jogo-do-tatu gsxuza/prospec-o-clientes gsxuza/psicologia-acolhedora gsxuza/rose-artesanatos-sistema gsxuza/sistema-operacional-Rose-Artesanatos-v2"
TOTAL=95

die() { echo "ERRO: $*" >&2; exit 1; }
cr() { tr -d '\r'; }

command -v gh >/dev/null 2>&1 || die "GitHub CLI não encontrado. Instale em https://cli.github.com"
LOGIN="$(gh api user --jq .login </dev/null 2>/dev/null | cr || true)"
[ "$LOGIN" = "$OWNER" ] || die "o gh está usando a conta \"${LOGIN:-nenhuma}\", não a $OWNER. Rode: gh auth login -s project -w (entrando como $OWNER no navegador) ou gh auth switch -u $OWNER"
gh project list --owner "$OWNER" --limit 1 </dev/null >/dev/null 2>&1 \
  || die "sem permissão para projects. Rode: gh auth refresh -s project"

if gh project list --owner "$OWNER" --limit 200 --format json --jq '.projects[].title' </dev/null | cr | grep -Fxq "$TITLE"; then
  die "já existe um project chamado \"$TITLE\". Apague ou renomeie esse antes de rodar de novo."
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "1/4 Criando o project..."
gh project create --owner "$OWNER" --title "$TITLE" --format json \
  --jq '"\(.number)\t\(.id)\t\(.url)"' </dev/null | cr > "$TMP/proj"
IFS=$'\t' read -r NUM PID URL < "$TMP/proj"
[ -n "${NUM:-}" ] && [ -n "${PID:-}" ] || die "não consegui criar o project"
gh project edit "$NUM" --owner "$OWNER" \
  --description "Backlog, em andamento, em revisão e concluídas de todos os repositórios" </dev/null >/dev/null 2>&1 || true

load_fields() {
  gh project field-list "$NUM" --owner "$OWNER" --limit 50 --format json \
    --jq '.fields[] | "\(.name)\t\(.id)"' </dev/null | cr > "$TMP/fields"
  gh project field-list "$NUM" --owner "$OWNER" --limit 50 --format json \
    --jq '.fields[] | select(.options != null) | .name as $f | .options[] | "\($f)\t\(.name)\t\(.id)"' </dev/null | cr > "$TMP/options"
}
field_id() { awk -F'\t' -v f="$1" '$1 == f { print $2; exit }' "$TMP/fields"; }
option_id() { awk -F'\t' -v f="$1" -v o="$2" '$1 == f && $2 == o { print $3; exit }' "$TMP/options"; }

echo "2/4 Configurando as colunas e o campo Projeto..."
load_fields
STATUS_FIELD="Status"
STATUS_ID="$(field_id Status)"
if ! gh api graphql -f id="$STATUS_ID" -f query='
mutation($id: ID!) {
  updateProjectV2Field(input: {fieldId: $id, singleSelectOptions: [
    {name: "Backlog",      color: GREEN,  description: "Ainda não começou"},
    {name: "Em andamento", color: YELLOW, description: "Sendo feito agora"},
    {name: "Em revisão",   color: BLUE,   description: "Pronto numa branch, esperando revisão ou merge"},
    {name: "Concluídas",   color: PURPLE, description: "Entregue"}
  ]}) { clientMutationId }
}' </dev/null >/dev/null 2>"$TMP/err"; then
  echo "   Não deu para renomear as opções do Status ($(head -c 200 "$TMP/err")); usando um campo \"Coluna\"."
  STATUS_FIELD="Coluna"
  gh project field-create "$NUM" --owner "$OWNER" --name "Coluna" --data-type SINGLE_SELECT \
    --single-select-options "Backlog,Em andamento,Em revisão,Concluídas" </dev/null >/dev/null
fi
gh project field-create "$NUM" --owner "$OWNER" --name "Projeto" --data-type SINGLE_SELECT \
  --single-select-options "$PROJETOS" </dev/null >/dev/null
load_fields
STATUS_FID="$(field_id "$STATUS_FIELD")"
PROJ_FID="$(field_id Projeto)"
[ -n "$STATUS_FID" ] && [ -n "$PROJ_FID" ] || die "campos do project não encontrados"

set_option() { # item-id campo-id nome-do-campo opção
  local oid
  oid="$(option_id "$3" "$4")"
  [ -n "$oid" ] || die "opção \"$4\" não existe no campo $3"
  gh project item-edit --id "$1" --project-id "$PID" --field-id "$2" \
    --single-select-option-id "$oid" </dev/null >/dev/null
}

echo "3/4 Adicionando $TOTAL cartões (leva alguns minutos)..."
n=0
while IFS=$'\t' read -r kind status projeto a b <&3; do
  [ -n "$kind" ] || continue
  n=$((n + 1))
  if [ "$kind" = "I" ]; then
    item="$(gh project item-add "$NUM" --owner "$OWNER" --url "$a" --format json --jq '.id' </dev/null | cr)"
    label="$a"
  else
    item="$(gh project item-create "$NUM" --owner "$OWNER" --title "$a" --body "$b" --format json --jq '.id' </dev/null | cr)"
    label="$a"
  fi
  [ -n "$item" ] || die "não consegui adicionar: $label"
  set_option "$item" "$STATUS_FID" "$STATUS_FIELD" "$status"
  set_option "$item" "$PROJ_FID" "Projeto" "$projeto"
  printf '   %3d/%d  %-13s %s\n' "$n" "$TOTAL" "$status" "$label"
done 3<<'DADOS'
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
DADOS

echo "4/4 Ligando o project aos repositórios..."
for r in $REPOS; do
  gh project link "$NUM" --owner "$OWNER" --repo "$r" </dev/null >/dev/null 2>&1 || true
done

cat <<FIM

Pronto: $URL

Falta só deixar a visualização como quadro (3 cliques):
  1. Abra o link acima, clique na setinha da aba "View 1" > Layout > Board.
  2. Na mesma setinha, Rename > "Kanban".
  3. Em View (canto direito) > Fields, marque "Projeto" e "Labels" para aparecerem nos cartões.
FIM
if [ "$STATUS_FIELD" = "Coluna" ]; then
  echo "  4. Em View > Column by, escolha \"Coluna\"."
fi
cat <<'FIM'

Em Workflows (canto superior direito), confira "Item closed" e "Pull request merged":
eles devem mover o cartão para "Concluídas".
FIM
