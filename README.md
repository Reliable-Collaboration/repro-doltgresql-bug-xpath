# DoltgreSQL 1.3.1: the `xml` type does not exist, and `xpath()` is not found

On DoltgreSQL 1.3.1 the `xml` type does not exist, and neither does the `xpath` function. A cast to `xml`,
a table column of type `xml`, and a call to `xpath` are each refused:

```
ERROR:  unable to resolve type `xml`
ERROR:  type "xml" does not exist
ERROR:  function: 'xpath' not found
```

PostgreSQL 18.6 runs the same three statements: it returns `<a>x</a>`, creates the table, and returns `{x}`.

## Reproduce it

You need Docker and a POSIX shell: Linux, macOS, or Windows with WSL. The first run downloads the two images.

```sh
git clone https://github.com/Reliable-Collaboration/repro-doltgresql-bug-xpath.git
cd repro-doltgresql-bug-xpath
./repro.sh
```

`repro.sh` starts PostgreSQL 18.6 and DoltgreSQL 1.3.1 in throwaway containers, waits until each accepts
connections, runs [`repro.sql`](repro.sql) on each with the `psql` client inside its container, and prints
the two outputs side by side. It exits 0 when DoltgreSQL's output is identical to PostgreSQL's and 1 when it
differs, and removes both containers either way.

To try another DoltgreSQL release, name its image (`POSTGRES_IMAGE` does the same for PostgreSQL):

```sh
DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
```

### Without the script

The same steps by hand, from the repository directory:

```sh
docker run -d --name repro-doltgresql-bug-xpath-postgres -e POSTGRES_PASSWORD=password postgres:18.6-bookworm
docker run -d --name repro-doltgresql-bug-xpath-doltgresql -e DOLTGRES_PASSWORD=password dolthub/doltgresql:1.3.1
docker cp repro.sql repro-doltgresql-bug-xpath-postgres:/tmp/repro.sql
docker cp repro.sql repro-doltgresql-bug-xpath-doltgresql:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-xpath-postgres psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-xpath-doltgresql psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f repro-doltgresql-bug-xpath-postgres repro-doltgresql-bug-xpath-doltgresql
```

If `docker exec` answers that the connection was refused, the server is still starting: wait a few seconds
and run it again.

## The test

[`repro.sql`](repro.sql):

```sql
-- A value of type xml.
SELECT '<a>x</a>'::xml AS doc;

-- A table column of type xml.
CREATE TABLE t (doc xml);

-- The xpath function over an xml value.
SELECT xpath('/a/text()', '<a>x</a>'::xml);
```

## Expected behavior

All three statements succeed. This is what PostgreSQL 18.6 does:

```
-- A value of type xml.
SELECT '<a>x</a>'::xml AS doc;
   doc    
----------
 <a>x</a>
(1 row)

-- A table column of type xml.
CREATE TABLE t (doc xml);
CREATE TABLE
-- The xpath function over an xml value.
SELECT xpath('/a/text()', '<a>x</a>'::xml);
 xpath 
-------
 {x}
(1 row)
```

## Actual behavior

All three statements fail. This is what DoltgreSQL 1.3.1 does:

```
-- A value of type xml.
SELECT '<a>x</a>'::xml AS doc;
psql:/tmp/repro.sql:2: ERROR:  unable to resolve type `xml`
-- A table column of type xml.
CREATE TABLE t (doc xml);
psql:/tmp/repro.sql:5: ERROR:  type "xml" does not exist
-- The xpath function over an xml value.
SELECT xpath('/a/text()', '<a>x</a>'::xml);
psql:/tmp/repro.sql:8: ERROR:  function: 'xpath' not found
```

## Side by side

The full output of `./repro.sh`:

```
Starting postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af
Starting dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851

Left: PostgreSQL. Right: DoltgreSQL. Lines that differ are marked with |.

-- A value of type xml.                                       -- A value of type xml.
SELECT '<a>x</a>'::xml AS doc;                                SELECT '<a>x</a>'::xml AS doc;
   doc                                                      | psql:/tmp/repro.sql:2: ERROR:  unable to resolve type `xml`
----------                                                  <
 <a>x</a>                                                   <
(1 row)                                                     <
                                                            <
-- A table column of type xml.                                -- A table column of type xml.
CREATE TABLE t (doc xml);                                     CREATE TABLE t (doc xml);
CREATE TABLE                                                | psql:/tmp/repro.sql:5: ERROR:  type "xml" does not exist
-- The xpath function over an xml value.                      -- The xpath function over an xml value.
SELECT xpath('/a/text()', '<a>x</a>'::xml);                   SELECT xpath('/a/text()', '<a>x</a>'::xml);
 xpath                                                      | psql:/tmp/repro.sql:8: ERROR:  function: 'xpath' not found
-------                                                     <
 {x}                                                        <
(1 row)                                                     <
                                                            <

Result: DoltgreSQL's output differs from PostgreSQL's on 3 line(s), marked with |.
```

## Other observations

Each was run with `psql` on DoltgreSQL 1.3.1 and on PostgreSQL 18.6, in containers from the same images:

- Without the cast, `SELECT xpath('/a/text()', '<a>x</a>');` answers the same `function: 'xpath' not found`,
  and so does `SELECT pg_catalog.xpath('/a/text()', '<a>x</a>');`. PostgreSQL returns `{x}` for both.
- `SELECT xpath_exists('/a', '<a>x</a>'::xml);` answers `function: 'xpath_exists' not found`. PostgreSQL
  returns `t`.
- Over a `text` column, `CREATE VIEW v2 AS SELECT id, xpath('/a/text()', doc::xml) AS x FROM t2;` answers
  `function: 'xpath' not found`, and `CREATE VIEW v3 AS SELECT id, doc::xml AS d FROM t2;` answers
  ``unable to resolve type `xml` ``. PostgreSQL creates both views.
- Spelled `pg_catalog.xml`, the type name is accepted, but the value is not `xml`:
  `SELECT pg_typeof('<a>x</a>'::pg_catalog.xml);` answers `unknown`, and `SELECT '<a>'::pg_catalog.xml AS malformed;`
  returns `<a>` without an error. PostgreSQL answers `xml`, and refuses `'<a>'` with `invalid XML content`.
- `CREATE TABLE t4 (doc pg_catalog.xml);` succeeds, and the column's `data_type` in
  `information_schema.columns` is `unknown`; `INSERT INTO t4 VALUES ('<a>');` then succeeds. On PostgreSQL the
  column's `data_type` is `xml`, and the insert fails with `invalid XML content`.
- `SELECT XMLPARSE(DOCUMENT '<a>x</a>');` answers `function: 'xmlparse' not found`; `xml_is_well_formed`,
  `xml_is_well_formed_document`, `xmlconcat` and `xmlcomment` answer the same error with their own names.
  PostgreSQL runs all five.
- `SELECT xmlelement(name a, 'x');` answers `at or near "a": syntax error`, and
  `SELECT * FROM XMLTABLE('/a' PASSING '<a>x</a>' COLUMNS v text PATH 'text()');` answers
  `at or near "passing": syntax error`. PostgreSQL returns `<a>x</a>` and `x`.
- `SELECT typname FROM pg_type WHERE typname = 'xml';` returns no row (PostgreSQL: `xml`, oid 142).

## Environment

- DoltgreSQL 1.3.1: image `dolthub/doltgresql:1.3.1`, digest
  `sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851`. Its bundled `psql` is 17.11.
- PostgreSQL 18.6: image `postgres:18.6-bookworm`, digest
  `sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af`. Its `psql` is 18.6.
- Reproduced on 2026-09-11 (UTC) with Docker 29.7.2 on Ubuntu 26.04.1 LTS under WSL 2 (Linux
  6.18.33.2-microsoft-standard-WSL2, x86_64).
