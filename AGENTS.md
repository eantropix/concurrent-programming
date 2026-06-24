# Guia de Implementação: Algoritmos de Pipeline em Elixir
**Documento de Referência para Agentes Antigravity**

Este documento detalha os conceitos fundamentais necessários para implementar os **Algoritmos de Pipeline** (como a *Multiplicação de Matrizes Distribuída*) utilizando a linguagem **Elixir**. O Elixir, rodando na máquina virtual BEAM, é nativamente projetado para esse tipo de arquitetura descentralizada baseada em troca de mensagens [1, 2].

---

## 1. O Paradigma de Pipeline (Revisão Teórica)
No Capítulo 9, um algoritmo de pipeline é definido como um padrão de interação onde a informação flui de um processo para outro [3]. 
*   **Trabalhadores (Workers):** Atuam como "filtros" ou estágios de uma linha de montagem. Recebem dados, realizam cálculos parciais e repassam o restante adiante [4].
*   **Coordenador (Coordinator):** Em um *closed pipeline* (pipeline fechado), um processo coordenador injeta os dados iniciais no primeiro trabalhador e coleta os resultados processados do último trabalhador [4].

---

## 2. O Modelo de Atores no Elixir
Para traduzir os processos do pseudocódigo do livro para Elixir, o agente deve utilizar o **Modelo de Atores** (*Actor Model*) [5].
*   **Processos Leves:** Em Elixir, processos não são *threads* do sistema operacional. São unidades isoladas gerenciadas pela máquina virtual (BEAM) com baixíssimo consumo de memória [5].
*   **Isolamento (Shared-Nothing):** Não existe memória compartilhada [2]. Variáveis globais ou *locks* (como semáforos) não são aplicáveis aqui. Todo o compartilhamento de dados ocorre estritamente via comunicação por mensagens [2, 5].

### Como Instanciar (Spawning)
Para criar a malha do pipeline (trabalhadores e o coordenador), utiliza-se a função `spawn/1` ou `spawn_link/1`, que retorna um Identificador de Processo (`PID`) [6]. O `PID` atua como o endereço (o "canal" unidirecional) para onde o estágio anterior enviará seus dados.

---

## 3. Primitivas de Comunicação (Send / Receive)
A arquitetura de pipeline do livro depende fortemente das primitivas `send` e `receive` [3]. O Elixir implementa isso de forma nativa e assíncrona:

*   **Envio Assíncrono (`send/2`):** O agente deve usar a função `send(pid, mensagem)` para empurrar os dados para o próximo trabalhador no pipeline [7]. O envio não bloqueia a execução do remetente [8].
*   **Recebimento Bloqueante (`receive`):** Cada trabalhador deve ter um bloco `receive do ... end`. O processo dormirá até que uma mensagem chegue em sua caixa de correio (*mailbox*) [7].
*   **Pattern Matching (Casamento de Padrões):** Ao receber dados (por exemplo, distinguir se a mensagem contém uma "linha da matriz A" ou uma "coluna da matriz B"), o agente deve usar a correspondência de padrões do Elixir diretamente no bloco `receive` para rotear a lógica [7, 9].

**Exemplo Conceitual de um Estágio do Pipeline:**
```elixir
def worker_loop(next_pid, state) do
  receive do
    {:row_a, row_data} ->
      # Processa os dados da linha
      new_state = compute(row_data, state)
      # Repassa dados para o próximo estágio do pipeline
      send(next_pid, {:row_a, row_data})
      # Chama recursivamente para aguardar a próxima mensagem
      worker_loop(next_pid, new_state)

    {:collect_results, coordinator_pid} ->
      send(coordinator_pid, {:result, state})
  end
end
