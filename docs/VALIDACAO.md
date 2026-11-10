# Validação e evidências da Fase 4

Este é um procedimento para executar e registrar resultados. Etapas descritas aqui não significam testes já realizados. Usar ambiente de teste para criar usuários, jogos, pedidos e avaliações; os scripts completos geram dados e podem recriar containers.

## Pré-requisitos locais

Clonar como pastas irmãs UsersAPI, CatalogAPI, PaymentsAPI, Orchestration, Outbox Processor e Notifications Lambda. Os dois últimos não estavam disponíveis na pasta desta revisão. Instalar .NET 10, Docker com Compose e PowerShell; Kubernetes exige `kubectl` e contexto previamente configurado. O Compose precisa suportar `!reset` e `!override` para o overlay híbrido.

Os comandos seguintes partem da pasta que contém os repositórios, salvo indicação diferente. Conferir as configurações antes de executar. Não copiar credenciais para o relatório ou capturas.

## Testes automatizados

```powershell
dotnet test ./FCG-UsersAPI/tests/UsersAPI.UnitTests/UsersAPI.UnitTests.csproj --configuration Release
dotnet test ./FCG-CatalogAPI/tests/CatalogAPI.UnitTests/CatalogAPI.UnitTests.csproj --configuration Release
dotnet test ./FCG-PaymentsAPI/tests/PaymentsAPI.UnitTests/PaymentsAPI.UnitTests.csproj --configuration Release
```

Para executar o teste real de MongoDB, com um Mongo local dedicado a testes já iniciado:

```powershell
$env:FCG_TEST_MONGO_CONNECTION = 'mongodb://localhost:27017'
dotnet test ./FCG-CatalogAPI/tests/CatalogAPI.UnitTests/CatalogAPI.UnitTests.csproj --configuration Release --filter FullyQualifiedName~MongoGameReviewStoreIntegrationTests
Remove-Item Env:FCG_TEST_MONGO_CONNECTION
```

Esse teste cria um banco com nome aleatório, valida índice/inserção/ordenação e remove somente esse banco ao terminar. Não configurado o ambiente, o teste é ignorado.

Registro da execução local de 10/11/2026: UsersAPI 16 aprovados; CatalogAPI 36 aprovados e 1 ignorado (MongoDB sem conexão de teste). PaymentsAPI não foi executada nessa revisão. O restore apontou NU1902/NU1903 em `System.Security.Cryptography.Pkcs` 9.0.4; registrar a resolução quando aplicada.

## Stack local completa

Na raiz de `FCG-Orchestration`, após disponibilizar todos os repositórios:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./start-local.ps1
docker compose ps
powershell -NoProfile -ExecutionPolicy Bypass -File ./test-apis.ps1
```

`start-local.ps1` compila/empacota a Lambda e executa `docker compose up --build --force-recreate -d`. A alternativa `test-apis.ps1 -StartDocker` prepara e testa a stack. Não executar os dois caminhos de preparação sem necessidade. Subir apenas `docker compose up --build` antes de gerar o pacote da Lambda pode deixar o LocalStack sem o artefato esperado.

Para Postman, importar `postman/FCG-Phase3.postman_collection.json` e executar na ordem. O nome histórico foi mantido: a coleção cobre JWT, catálogo, cache, compra, avaliações e status de notificações. Ela ainda não cobre a busca da branch não integrada. Bruno oferece requisições em `bruno/`, com ambiente `Docker`.

## Evidência de NoSQL

1. Criar um jogo com token `Admin` e registrar seu ID.
2. Com token de usuário, enviar `POST /api/games/{id}/reviews` com `rating` entre 1 e 5 e `comment` não vazio, até 500 caracteres.
3. Consultar `GET /api/games/{id}/reviews` e conferir autor, jogo, nota e comentário.
4. Conferir o documento na collection `reviews` do banco configurado em `Mongo__Database` e o índice por `gameId`.
5. Registrar status HTTP, documento sem dados pessoais desnecessários e revisão do código executado. Após configurar persistência, verificar recuperação dos dados em reinício controlado.

## Evidência de cache e desempenho

Confirmar `ConnectionStrings__Redis` na aplicação. O fallback de memória em um processo não comprova cache distribuído.

1. Criar/editar um jogo para invalidar a listagem; executar a mesma consulta paginada duas vezes.
2. Conferir `Cache miss` e `Cache hit` nos logs do CatalogAPI e chaves com prefixo `fcg:` no Redis. Não usar `FLUSHALL` em banco compartilhado.
3. Medir várias repetições em condições iguais, identificando consultas frias e aquecidas; manter gateway, parâmetros, volume de dados e concorrência iguais.
4. Separar aquecimento de aplicação/conexões do efeito do cache. Registrar latências, quantidade de amostras e mediana/p95 quando houver amostra suficiente. Duas requisições isoladas não provam ganho consistente.
5. Criar, editar e desativar jogo, verificando que a próxima listagem reflete a mudança.

| Data / ambiente / revisão | Consulta e volume de dados | Amostras | Sem hit (ms) | Com hit (ms) | Evidência Redis/logs |
|---|---|---|---|---|---|
| A preencher após medição | A preencher | A preencher | Não medido | Não medido | A anexar |

## Evidência de busca

Executar somente depois de integrar a busca na revisão entregue e configurar Elasticsearch/OpenSearch gerenciado:

1. Criar um jogo e localizá-lo em `/search?q=...` sem consulta textual direta ao SQL.
2. Consultar com um erro de digitação e conferir resultado relevante.
3. Criar resultados concorrentes e conferir ordenação por score/relevância.
4. Editar o título/descrição e verificar atualização do índice; desativar o jogo e verificar que deixa de aparecer.
5. Validar reindexação e recuperação após indisponibilidade do motor. Registrar o endpoint/serviço gerenciado sem credenciais.

## Evidência cloud e entrega contínua

Preparar o provedor e a pipeline antes de executar este roteiro. Ainda não há workflow de deploy no código examinado.

1. Registrar provedor, região, cluster gerenciado, registry privado nativo e serviço de busca gerenciado.
2. Conferir o contexto correto com `kubectl config current-context`; registrar `kubectl get nodes`, `kubectl get deployments`, `kubectl get pods` e `kubectl get services` no namespace adotado.
3. Conferir imagem/tag/digest em execução e URL pública do gateway. Não coletar conteúdo de Secrets, tokens ou kubeconfig.
4. Fazer uma alteração identificável de comportamento, passar pelos testes e integrar à branch principal (`master` neste projeto).
5. Registrar a execução da pipeline: testes, imagem versionada, push ao registry e deploy automático no cluster.
6. Acompanhar `kubectl rollout status deployment/users-api` e/ou `deployment/catalog-api`, acrescentando `-n` com o namespace correto quando necessário.
7. Durante o rollout, enviar requisições contínuas e registrar códigos HTTP/latência. Conferir réplicas prontas e comportamento novo na URL pública.
8. Registrar o procedimento de rollback e a versão anterior disponível. Reexecutar testes funcionais após o deploy.

O nome `docker-compose.production.yml` não substitui essas evidências: esse overlay executa componentes localmente com notificações na AWS.

## Fechamento da documentação

- [ ] Atualizar a [matriz](FASE4.md) apenas com resultados comprovados.
- [ ] Preencher grupo, integrantes e Discord nos dois formatos do relatório.
- [ ] Registrar URLs públicas, revisão entregue e links de evidências sem segredos.
- [ ] Publicar as alterações documentais e conferir acesso do avaliador aos repositórios.
- [ ] Completar o campo de link do vídeo quando ele existir; produção do vídeo fora desta tarefa.
- [ ] Revisar o relatório final para remover campos “a preencher” antes da submissão.
