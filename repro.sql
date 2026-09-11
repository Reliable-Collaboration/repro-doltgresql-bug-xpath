-- A value of type xml.
SELECT '<a>x</a>'::xml AS doc;

-- A table column of type xml.
CREATE TABLE t (doc xml);

-- The xpath function over an xml value.
SELECT xpath('/a/text()', '<a>x</a>'::xml);
