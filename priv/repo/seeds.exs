NimbleCSV.define(SimplyPut.ClearCorpusCSV, separator: ",", escape: "\"")

alias SimplyPut.ClearCorpusCSV
alias SimplyPut.CorpusItem
alias SimplyPut.Repo

csv_path = Path.join(__DIR__, "clear_corpus_sample.csv")

csv_path
|> File.read!()
|> ClearCorpusCSV.parse_string()
|> Enum.each(fn [_id, title, author, source_text, source_grade, license, url] ->
  attrs = %{
    title: title,
    author: author,
    source_text: source_text,
    source_grade: String.to_float(source_grade),
    license: license,
    url: url
  }

  %CorpusItem{}
  |> CorpusItem.changeset(attrs)
  |> Repo.insert!()
end)

IO.puts("Seeded #{Repo.aggregate(CorpusItem, :count)} corpus items.")
