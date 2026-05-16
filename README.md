# claude-usage-panel

Widget para o painel do **XFCE** (Linux Mint, Xubuntu, etc) que mostra o uso de tokens do **Claude Code** em tempo real — sessão de 5h, cota semanal de 7d, status da conta e status da Anthropic.

![preview]( <!-- coloque um print aqui depois --> )

## O que mostra

No painel:

```
[🤖] ● 🜁 53% 4h17m | 🜃 11%
```

- **🤖** — pixel-art do [claudepix](https://claudepix.vercel.app)
- **●** — bolinha colorida com o status do componente "Claude Code" na [status page da Anthropic](https://status.anthropic.com)
- **🜁** — utilização da janela de 5h, com tempo até o reset
- **🜃** — utilização da janela de 7d
- Cores: verde <50%, laranja 50–80%, vermelho ≥80%

No tooltip:

```
Sessão (5h): 53% — reseta hoje às 14:49 (em 4h 17m)
Semanal (7d): 11% — reseta ter 19/05 às 10:59 (em 3d 0h)
Status conta: permitido
Claude Code: Operacional
```

Quando há incidente ativo, aparece também o nome e a última atualização. Quando há manutenção agendada nas próximas 24h, aparece o horário.

Click esquerdo → abre `claude.ai/settings/usage`.

## Como funciona

Lê o token OAuth de `~/.claude/.credentials.json` (o mesmo que o `claude` CLI usa) e chama dois endpoints:

- `GET https://api.anthropic.com/api/oauth/usage` — utilização das janelas 5h/7d, cota Opus/Sonnet dedicada (quando disponível no plano Max), créditos extra. **Não consome budget** — é leitura pura.
- `GET https://status.anthropic.com/api/v2/summary.json` — componentes, incidentes não-resolvidos, manutenções agendadas.

Cache local em `/tmp/` por 55s para evitar excesso de requests (o `genmon` costuma fazer poll a cada 60s).

## Instalação

### 1. Dependências

```bash
sudo apt install xfce4-genmon-plugin curl python3
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

### 4. Adicione ao painel XFCE

1. Clique direito no painel → *Painel* → *Adicionar novos itens…*
2. Selecione **Generic Monitor**.
3. Botão direito no widget novo → *Properties*:
   - **Command**: `bash /caminho/para/claude-usage-panel.sh`
   - **Period (seconds)**: `60`
   - **Label**: desmarcado
   - **Use a font**: opcional

## Personalização

- **TTL do cache**: variável `CACHE_TTL` (default 55s) no topo do script.
- **Limiares de cor**: função `colorize()`.
- **Caminho do ícone**: variável `ICON`.
- **Click**: linha `<txtclick>` no final do script. Por exemplo, trocar para abrir a status page quando há incidente.

## Por que esse trabalho todo?

O Claude Code não expõe widget de painel oficial no Linux, e o dashboard de uso vive atrás de 2 cliques no `claude.ai`. Ter o número visível no canto da tela ajuda a entender o ritmo de gasto e antecipar quando vai bater o limite — especialmente nos planos Pro/Max em que a cota é fixa por janela.

## Licença

MIT.
