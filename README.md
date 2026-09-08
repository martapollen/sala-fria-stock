# Sala Fria — Registo de Movimentos de Stock

App estática (sem build, sem Node) para registar entradas e saídas dos
componentes da sala fria. Base de dados em [Supabase](https://supabase.com),
código em GitHub, publicado no [Vercel](https://vercel.com).

Não precisas de instalar nada neste Mac — nem Node, nem CLIs. Os três passos
abaixo usam só o browser e o `git` (já instalado).

## 1. Criar a base de dados no Supabase

1. Em [supabase.com](https://supabase.com), cria um novo projeto (qualquer
   nome e região; guarda a password da base de dados nalgum sítio seguro,
   embora não a vás precisar aqui).
2. Depois do projeto ficar pronto, abre **SQL Editor** (barra lateral) →
   **New query**.
3. Copia todo o conteúdo de [`supabase/schema.sql`](supabase/schema.sql)
   deste projeto, cola no editor, e clica **Run**. Isto cria as tabelas
   `items` e `movements`, as regras de acesso, e carrega os 134 componentes.
4. Vai a **Project Settings → API**. Vais precisar de dois valores:
   - **Project URL**
   - **anon / public key**

## 2. Configurar a app com esses valores

Abre [`config.js`](config.js) neste projeto e substitui os dois valores de
exemplo pelos que copiaste no passo anterior:

```js
window.SUPABASE_URL = "https://xxxxxxxx.supabase.co";
window.SUPABASE_ANON_KEY = "ey...";
```

Estes valores são seguros para ficarem no código — não são segredos; a
segurança real está nas políticas de RLS já definidas no `schema.sql`
(qualquer pessoa pode ler e registar movimentos, ninguém pode editar o
catálogo de componentes por essa via).

## 3. Publicar no GitHub + Vercel

No Terminal, dentro desta pasta:

```bash
git init
git add .
git commit -m "Primeira versão"
```

Depois, no site do GitHub, cria um repositório novo (privado ou público —
não importa) e segue as instruções que ele mostra para "push an existing
repository":

```bash
git remote add origin https://github.com/<o-teu-user>/sala-fria-stock.git
git branch -M main
git push -u origin main
```

Por fim, no [vercel.com](https://vercel.com):

1. **Add New → Project**.
2. Escolhe o repositório `sala-fria-stock` que acabaste de criar.
3. Não precisas de mudar nenhuma definição (é um site estático — o Vercel
   deteta isso automaticamente). Clica **Deploy**.

A partir daqui, qualquer `git push` para o `main` publica automaticamente
uma nova versão — não precisas de repetir o passo do Vercel.

## Estrutura do projeto

```
index.html            a app (HTML/CSS/JS, sem build)
config.js              URL + chave do Supabase (editas isto uma vez)
assets/fonts/          tipografia Avantt (marca Pollen)
assets/img/            padrão de fundo do cabeçalho
supabase/schema.sql    tabelas, permissões, e os 134 componentes
```

## Se precisares de atualizar o catálogo de componentes mais tarde

O catálogo (`items`) só é editável a partir do SQL Editor do Supabase — a
app só o lê. Para adicionar ou corrigir um componente, corre um `insert`
ou `update` diretamente lá, ou volta a correr `supabase/schema.sql`
(é seguro repetir: atualiza os existentes em vez de duplicar).
