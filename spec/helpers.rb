require 'active_support/core_ext/hash/indifferent_access'

module QcHelpers
  def execute(sql, *args)
    QC.default_conn_adapter.execute(sql, *args)
  end

  def find_job(id)
    execute("SELECT * FROM #{QC::TABLE_NAME} WHERE id = $1", id).with_indifferent_access
  end
end
