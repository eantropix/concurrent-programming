# Pipeline Algorithms: Multiplicação de Matrizes

## 1. Introdução
A multiplicação de duas matrizes quadradas $A$ e $B$ de dimensão $N \times N$, resultando em uma matriz $C$, é uma operação computacionalmente intensiva com complexidade de tempo sequencial clássica de $O(N^3)$. Para o cálculo de uma linha da matriz, o cálculo das outras linhas não a afetam de forma alguma. Por isso, é interessante a paralelização dessa operação para aumentar o desempenho da multiplicação.

---

## 2. O Problema da Paralelização Ingênua com Workers
Uma abordagem simples de paralelizar a multiplicação de matrizes consiste em instanciar $N$ *workers* independentes abaixo de um coordenador. Cada worker $i$ calcula uma única linha correspondente da matriz resultante, ou seja, a linha $C[i, *]$. Assim, cada worker precisa receber do coordenador:

1. **Uma linha da matriz $A$:** O vetor $A[i, *]$, que contém $N$ elementos (ao qual apenas ele utilizará).
2. **A matriz $B$:** Uma vez que cada elemento $C[i, j]$ (para $j$ de $0$ a $N-1$) exige o produto interno da linha $i$ de $A$ com a coluna $j$ de $B$, o worker precisa ter acesso a todas as colunas de $B$.

Mas essa implementação tem alguns problemas, como:

* **Gargalo do Coordenador:** O coordenador precisará enviar a matriz $B$ completa para cada um dos $N$ workers. A transmissão de $N$ matrizes de tamanho $N \times N$ resulta em uma complexidade de comunicação total de $O(N^3)$ dados trafegados na rede ou canais internos. O processo coordenador pode se tornar um gargalo no sistema devido ao alto overhead de envio.
* **Alto Consumo de Memória:** Cada worker precisa alocar espaço em memória para armazenar a matriz $B$ completa ($N^2$ elementos). Em sistemas com nós de processamento limitados ou matrizes de grande escala, isso pode ser muito custoso ou até mesmo inviável.
* **Ineficiência:** Os workers permanecem ociosos até que a totalidade dos dados da matriz $B$ seja transmitida e recebida, impedindo a sobreposição de tempo de transmissão com o tempo de cálculo (ocultação de latência).

---

## 3. Algoritmo de Pipeline
Para superar as limitações da abordagem ingênua, adota-se um modelo de **Pipeline**. Em vez de utilizar uma comunicação centralizada do tipo *broadcast*, os workers são organizados em uma cadeia de comunicação:

$$\text{Coordenador} \rightarrow \text{Worker}_0 \rightarrow \text{Worker}_1 \rightarrow \dots \rightarrow \text{Worker}_{N-1} \rightarrow \text{Coordenador}$$

Nesse modelo, os dados de entrada são transmitidos sequencialmente a partir do coordenador para o primeiro worker, então entre vizinhos adjacentes na cadeia, para ter o resultado retornando ao coordenador pelo último worker. Dessa forma, é possível distribuir melhor o tráfego de rede e minimizar o uso de memória.

### A. Distribuição da Matriz A
1. O coordenador envia as linhas da matriz $A$ uma a uma para o primeiro elemento da cadeia ($\text{Worker}_0$).
2. Quando o $\text{Worker}_i$ recebe uma linha da matriz $A$, ele fica com uma linha e repassa as outras adiante.
3. No final dessa etapa, cada worker tem exatamente uma linha de $A$. A complexidade de memória para a matriz $A$ em cada worker cai de $O(N^2)$ para $O(N)$.

### B. Cálculo com Colunas da Matriz B
1. O coordenador envia as colunas da matriz $B$ de forma sequencial para o $\text{Worker}_0$.
2. Ao receber uma coluna de $B$, o $\text{Worker}_i$:
   * Encaminha a coluna recebida para o próximo worker na fila ($\text{Worker}_{i+1}$), caso não seja o último da cadeia.
   * Executa o produto interno de sua linha atribuída de $A$ com a coluna recebida de $B$, gerando um elemento da sua linha de resultados de $C$.
3. Como o envio ao próximo worker ocorre antes do processamento, o fluxo de colunas flui como uma "onda" pelo pipeline. Quando o $\text{Worker}_0$ está processando a segunda coluna, o $\text{Worker}_1$ já está computando a primeira, garantindo um maior grau de paralelismo.

### C. Coleta de Resultados
1. Cada worker $i$ produziu uma linha resultante $C[i, *]$ contendo $N$ elementos.
2. Ao concluir seus cálculos, o $\text{Worker}_i$ envia sua própria linha resultante para o próximo nó.
3. Posteriormente, o worker entra em modo de repetição: ele aguarda as linhas resultantes dos workers que o antecedem no pipeline ($\text{Worker}_0$ a $\text{Worker}_{i-1}$) e as repassa fielmente ao próximo nó.
4. O último worker da cadeia ($\text{Worker}_{N-1}$), que está conectado de volta ao Coordenador, escoa todas as linhas resultantes. O coordenador recebe as linhas em ordem reversa (do worker $N-1$ ao worker $0$), bastando remontar a matriz final.

---

## 4. Algoritmo em Código Elixir (`pipeline.ex`)

### Spawn Conectado dos Workers
Na função `multiply/2`, os workers são instanciados em ordem reversa para que a passagem de PIDs ocorra de forma correta:
```elixir
first_worker_pid =
  Enum.reduce((matrix_size - 1)..0//-1, coordinator_pid, fn worker_index, next_pid ->
    spawn_link(fn -> worker(worker_index, matrix_size, next_pid) end)
  end)
```
* **Mecanismo:** A redução começa a partir do último worker ($N-1$), que recebe o PID do `coordinator` como seu `next_pid`. 
* Cada iteração anterior instancia um worker passando o PID do worker recém-criado.
* Ao final da redução, obtemos o PID do primeiro worker (`first_worker_pid` ou `Worker 0`), que servirá como ponto de entrada para o fluxo de dados.

### Fluxo de um Worker
O ciclo de execução de cada processo trabalhador segue estritamente as três etapas da topologia de pipeline:

#### 1. Retenção e Repasse da Matriz A
```elixir
my_row_a =
  receive do
    {:row_a, row} -> row
  end

if worker_index < matrix_size - 1 do
  for _ <- (worker_index + 1)..(matrix_size - 1) do
    receive do
      {:row_a, row} -> send(next_pid, {:row_a, row})
    end
  end
end
```
Cada worker bloqueia no `receive` para capturar a primeira linha `{:row_a, row}` que chega até ele. Logo após, realiza um loop para receber as linhas seguintes e encaminhá-las para o `next_pid`.

#### 2. Processamento em Pipeline da Matriz B
```elixir
my_row_c =
  for _j <- 0..(matrix_size - 1) do
    col_b =
      receive do
        {:col_b, col} -> col
      end

    if worker_index < matrix_size - 1 do
      send(next_pid, {:col_b, col_b})
    end

    inner_product(my_row_a, col_b)
  end
```
O worker realiza um loop de $N$ iterações (uma para cada coluna). Para cada coluna recebida de $B$, ele a envia para o próximo worker na cadeia (`send(next_pid, {:col_b, col_b})`) antes de calcular o produto interno (`inner_product/2`) localmente. Isto garante que a coluna continue viajando pelo pipeline enquanto o worker atual calcula sua fração do resultado.

#### 3. Repasse dos Resultados de C
```elixir
send(next_pid, {:result, worker_index, my_row_c})

if worker_index > 0 do
  for _i <- 0..(worker_index - 1) do
    receive do
      {:result, prev_w, prev_row_c} ->
        send(next_pid, {:result, prev_w, prev_row_c})
    end
  end
end
```
Após calcular sua própria linha da matriz resultante (`my_row_c`), o worker a envia para a frente (`{:result, worker_index, my_row_c}`). Posteriormente, se o worker atual não for o de índice $0$ (o primeiro), ele aguarda e repassa todas as mensagens de resultado dos predecessores.

### Coleta e Reconstrução pelo Coordenador
Após a cadeia de workers processar e escoar os resultados de volta para o coordenador, este executa as etapas finais de coleta e remontagem da matriz resultante:

```elixir
# recebe linhas de c 
c_rows =
  Enum.reduce((matrix_size - 1)..0//-1, %{}, fn i, acc ->
    receive do
      {:result, ^i, row_c} -> Map.put(acc, i, row_c)
    end
  end)

# refaz c
Enum.map(0..(matrix_size - 1), fn i -> Map.get(c_rows, i) end)
```

* O coordenador realiza uma redução decrescente (`(matrix_size - 1)..0//-1`) para coletar as linhas de $C$ em ordem reversa (uma vez que elas chegam a partir do último worker da cadeia, do índice $N-1$ até $0$). O uso do operador de pin (`^i`) no *pattern matching* garante que cada linha seja consumida da caixa de mensagens de forma estrita e indexada.
* As linhas recebidas são armazenadas em um mapa temporário indexado. Por fim, o coordenador itera de $0$ até $N-1$ (`Enum.map(0..(matrix_size - 1))`) para obter os valores na ordem correta, gerando a matriz final $C$ como uma lista de listas ordenada.

---

## 5. Vantagens do Algoritmo em Pipeline
A arquitetura implementada traz benefícios substanciais para o sistema concorrente:

1. **Coordenador sem Gargalos:** O coordenador não realiza *broadcast*, apenas se comunicando com um worker de entrada (`Worker 0`) e recebendo a resposta de um worker de saída  e recebe as respostas ordenadas de um worker de saída (`Worker N-1`).
2. **Eficiência de Memória:** Cada worker aloca espaço em memória para apenas uma linha de $A$ e uma única coluna de $B$ por vez, sendo menos custoso que armazenar a matriz $B$ ($N^2$ elementos).
