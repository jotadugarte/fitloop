# frozen_string_literal: true

# [REQ-FIT-AUTH-002] Placeholder legal pages until FU-LEGAL-001 copy ships (D16).
class LegalController < ApplicationController
  layout "minimal"

  def terms
    @version = TermsVersion.current
  end

  def privacy
    @version = TermsVersion.current
  end
end
