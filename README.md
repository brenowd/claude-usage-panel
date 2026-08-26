# claude-usage-panel

Widget para o painel do **XFCE** ou **Cinnamon** (Linux Mint) que mostra o uso de tokens do **Claude Code** em tempo real — sessão de 5h, cota semanal de 7d, status da conta e status da Anthropic.

> Detecta automaticamente o ambiente (Cinnamon ou XFCE) e formata a saída para o applet correto.

![preview]( <!-- coloque um print aqui depois --> )

## O que mostra

No painel:

```
[🤖] ● 🜁 53% 4h17m | 🜃 11%
```

- **🤖** — pixel-art do [claudepix](https://claudepix.vercel.app)
- **●** — bolinha colorida com o status do componente "Claude Code" na [status page da Anthropic](https://status.anthropic.com)
- **🜁** — utilização da janela de 5h, com tempo até o reset
- **🜃** — o **maior** limite semanal (geral ou por modelo, ex. Fable) — assim uma cota de modelo prestes a estourar não fica escondida atrás da geral
- Cores: severidade reportada pela API quando disponível; senão verde <50%, laranja 50–80%, vermelho ≥80%

No tooltip:

```
Sessão (5h): 53% — reseta hoje às 14:49 (em 4h 17m)
Semanal (7d): 11% — reseta ter 19/05 às 10:59 (em 3d 0h)
Fable (7d): 3% — reseta ter 19/05 às 10:59
No ritmo atual, sessão esgota em ~1h 10m
Status conta: permitido
Claude Code: Operacional
```

- Cotas semanais **por modelo** (Fable, etc.) aparecem automaticamente conforme a API as reporta.
- **Burn rate**: com ≥5 min de histórico na sessão, estima quando a janela de 5h esgota no ritmo atual.
- Créditos extra / spend aparecem quando habilitados na conta.

Quando há incidente ativo, aparece também o nome e a última atualização. Quando há manutenção agendada nas próximas 24h, aparece o horário.

Click esquerdo → abre `claude.ai/settings/usage`.

## Notificações

Se `notify-send` estiver disponível, o widget dispara notificações de desktop ao cruzar limiares da sessão de 5h:

- **≥80%** — aviso normal
- **≥95%** — aviso crítico
- **reset detectado** (queda ≥30 pontos vindo de ≥80%) — "quota liberada"

## Forçar atualização

```bash
bash claude-usage-panel.sh refresh
```

Limpa os caches; a próxima execução do applet busca dados novos. Se o token OAuth expirar, o widget mostra `⟳ login` — reautentique rodando `claude` no terminal.

## Detecção automática

O script detecta o ambiente automaticamente:

| Desktop | Formato de saída | Applet necessário |
|---|---|---|
| XFCE | Genmon (`<txt>`, `<tool>`, `<img>`) | `xfce4-genmon-plugin` |
| Cinnamon | XML (`CommandRunner@appdevsw`) | `CommandRunner` (Cinnamon Spices) |

A detecção usa `$XDG_CURRENT_DESKTOP`, `$GDMSESSION`, e `pgrep` como fallback.

## Como funciona

Lê o token OAuth de `~/.claude/.credentials.json` (o mesmo que o `claude` CLI usa) e chama dois endpoints:

- `GET https://api.anthropic.com/api/oauth/usage` — utilização das janelas 5h/7d, cota Opus/Sonnet dedicada (quando disponível no plano Max), créditos extra. **Não consome budget** — é leitura pura.
- `GET https://status.anthropic.com/api/v2/summary.json` — componentes, incidentes não-resolvidos, manutenções agendadas.

Cache local em `/tmp/` por 55s para evitar excesso de requests (o `genmon` costuma fazer poll a cada 60s).

## Instalação

### 1. Dependências

```bash
sudo apt install xfce4-genmon-plugin curl python3   # XFCE
# ou
sudo apt install curl python3                        # Cinnamon + CommandRunner applet (GUI)
```

### 2. Coloque o script onde quiser

```bash
git clone git@github.com:SEU_USER/claude-usage-panel.git ~/.local/share/claude-usage-panel
chmod +x ~/.local/share/claude-usage-panel/claude-usage-panel.sh
```

### 3. Ícone (opcional)

O script tenta carregar `~/.local/share/icons/claude/claude-robot.png`. Se não existir, o ícone simplesmente é omitido.

Para gerar o robozinho a partir do [claudepix](https://claudepix.vercel.app) ou usar o asterisco oficial:

```bash
# Asterisco oficial Claude (laranja)
mkdir -p ~/.local/share/icons/claude
curl -sL "https://claude.ai/favicon.svg" -o /tmp/claude.svg
inkscape /tmp/claude.svg -w 24 -h 24 -o ~/.local/share/icons/claude/claude-robot.png
```

### 4. Adicione ao painel

#### XFCE

1. Clique direito no painel → *Painel* → *Adicionar novos itens…*
2. Selecione **Generic Monitor**.
3. Botão direito no widget novo → *Properties*:
   - **Command**: `bash /caminho/para/claude-usage-panel.sh`
   - **Period (seconds)**: `60`
   - **Label**: desmarcado
   - **Use a font**: opcional

#### Cinnamon

1. Clique direito no painel → *Applets* → aba *Download* → procure **CommandRunner** → instale.
2. Na aba *Installed*, selecione **CommandRunner** → ➕ (Add to panel).
3. Clique direito no applet novo → *Configure*:
   - **Command**: `bash /caminho/para/claude-usage-panel.sh`
   - **Run interval**: `60` (seconds)
   - **Click Command**: `xdg-open https://claude.ai/settings/usage`

## Personalização

- **TTL do cache**: variável `CACHE_TTL` (default 55s) no topo do script.
- **Limiares de cor**: função `colorize()`.
- **Caminho do ícone**: variável `ICON`.
- **Click**: linha `<txtclick>` no final do script. Por exemplo, trocar para abrir a status page quando há incidente.

## Por que esse trabalho todo?

O Claude Code não expõe widget de painel oficial no Linux, e o dashboard de uso vive atrás de 2 cliques no `claude.ai`. Ter o número visível no canto da tela ajuda a entender o ritmo de gasto e antecipar quando vai bater o limite — especialmente nos planos Pro/Max em que a cota é fixa por janela.

## Licença

MIT.
