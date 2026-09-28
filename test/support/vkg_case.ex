defmodule AshR2RML.VKGCase do
  @moduledoc false
  alias AshR2RML.OBDA.Observation
  alias AshR2RML.VKG.{Catalog, Contract, Planner, SourceIdentity}

  def contract(id \\ "customer", opts \\ []) do
    source=Keyword.get(opts,:source,"urn:source:"<>id)
    graph=Keyword.get(opts,:graph,"urn:graph:"<>id)
    template=Keyword.get(opts,:subject_template,"https://example.org/"<>id<>"/{id}")
    {:ok,identity}=SourceIdentity.new(%{id:id,uri:source,graph:graph,subject_template:template,version:"1"})
    %Contract{id:id,source:source,graph:graph,source_sha256:identity.sha256,
      mapping_sha256:String.duplicate("a",64),query_sha256:String.duplicate("b",64),
      subject_template:template,mapping_path:"/tmp/"<>id<>".ttl",query_path:"/tmp/"<>id<>".rq",
      version:"1",capabilities:Keyword.get(opts,:capabilities,[:select,:filter,:join]),authority: :NONE}
  end

  def catalog(ids \\ ["customer"]) do
    {:ok,catalog}=ids |> Enum.map(&contract/1) |> Catalog.new()
    catalog
  end

  def plan(ids \\ ["customer"]) do
    catalog=catalog(ids)
    {:ok,plan}=Planner.plan(catalog,ids)
    {catalog,plan}
  end

  defmodule FakeEngine do
    def execute(stage,opts) do
      rows=Keyword.get(opts,:fake_rows,%{})
      stage_rows=Map.get(rows,stage.contract_id,[%{"subject"=>"https://example.org/"<>stage.contract_id<>"/1","name"=>String.capitalize(stage.contract_id)}])
      digest=:crypto.hash(:sha256,:erlang.term_to_binary({stage.contract_id,stage_rows},[:deterministic])) |> Base.encode16(case: :lower)
      {:ok,%Observation{status: :PARTIAL_ALIVE,standing: :test_double_only,system: :fake_vkg,
        system_version:"1",evidence_kind: :injected_runner,exit_status:0,observation_sha256:digest,
        output_sha256:digest,output_bytes:byte_size(:erlang.term_to_binary(stage_rows)),
        row_count:length(stage_rows),duration_ms:1,bounded?:true,rows:stage_rows}}
    end
  end

  defmodule RefusingEngine do
    def execute(stage,_opts) do
      refusal=AshR2RML.Refusal.new(:REFUSED_OBDA_EXECUTION,stage.contract_id,"synthetic refusal",%{})
      {:error,%Observation{status: :REFUSED,standing: :test_double_only,system: :fake_vkg,
        system_version:"1",evidence_kind: :injected_runner,refusal:refusal,bounded?:true,rows:[]}}
    end
  end
end
