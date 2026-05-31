# frozen_string_literal: true

# Maps legacy project_* URL helpers to session-scoped /taller routes (no id in the address bar).
module WorkshopUrlHelper
  def project_path(*_args, **kwargs)
    workshop_path(**kwargs)
  end

  def edit_project_path(*_args, **kwargs)
    workshop_path(**kwargs)
  end

  def nesting_parameters_project_path(*_args, **kwargs)
    nesting_parameters_workshop_path(**kwargs)
  end

  def workspace_project_path(*_args, **kwargs)
    workspace_workshop_path(**kwargs)
  end

  def nesting_sync_project_path(*_args, **kwargs)
    nesting_sync_workshop_path(**kwargs)
  end

  def nested_dxf_project_path(*_args, **kwargs)
    nested_dxf_workshop_path(**kwargs)
  end

  def download_paywall_project_path(*_args, **kwargs)
    download_paywall_workshop_path(**kwargs)
  end

  def orphan_dxf_project_path(*args, **kwargs)
    piece_index = kwargs[:piece_index] || args[1]
    orphan_dxf_workshop_path(piece_index: piece_index, **kwargs.except(:piece_index))
  end

  def project_layers_path(*_args, **kwargs)
    workshop_layers_path(**kwargs)
  end

  def project_input_dxf_files_path(*_args, **kwargs)
    workshop_input_dxf_files_path(**kwargs)
  end

  def project_input_dxf_file_path(*args, **kwargs)
    record = args[1]
    id = kwargs[:id] || record&.id
    workshop_input_dxf_file_path(id: id, **kwargs.except(:id))
  end

  def project_nesting_runs_path(*_args, **kwargs)
    workshop_nesting_runs_path(**kwargs)
  end

  def cancel_project_nesting_run_path(*args, **kwargs)
    run = args[1]
    id = kwargs[:id] || run&.id
    cancel_workshop_nesting_run_path(id: id, **kwargs.except(:id))
  end

  def project_orphan_resolution_path(*args, **kwargs)
    piece_key = kwargs[:piece_key] || args[1]
    workshop_orphan_resolution_path(piece_key: piece_key, **kwargs.except(:piece_key))
  end

  def confirm_manual_project_orphan_resolution_path(*args, **kwargs)
    piece_key = kwargs[:piece_key] || args[1]
    confirm_manual_workshop_orphan_resolution_path(piece_key: piece_key, **kwargs.except(:piece_key))
  end

  def accept_project_orphan_split_proposal_path(*args, **kwargs)
    piece_key = kwargs[:piece_key] || args[1]
    accept_orphan_split_proposal_workshop_path(piece_key: piece_key, **kwargs.except(:piece_key))
  end

  def reject_project_orphan_split_proposal_path(*args, **kwargs)
    piece_key = kwargs[:piece_key] || args[1]
    reject_orphan_split_proposal_workshop_path(piece_key: piece_key, **kwargs.except(:piece_key))
  end

  def regenerate_project_orphan_split_proposal_path(*args, **kwargs)
    piece_key = kwargs[:piece_key] || args[1]
    regenerate_orphan_split_proposal_workshop_path(piece_key: piece_key, **kwargs.except(:piece_key))
  end
end
