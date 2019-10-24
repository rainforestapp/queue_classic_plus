module QcHelpers
  def execute(sql, *args)
    QC.default_conn_adapter.execute(sql, *args)
  end

  def find_job(id)
    execute("SELECT * FROM #{QC.table_name} WHERE id = $1", id)
  end
end
