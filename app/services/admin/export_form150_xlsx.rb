# frozen_string_literal: true

require "axlsx"

module Admin
  # [REQ-FIT-ADMIN-001] Formulario 150 (IVA01) XLSX export with formula-linked soporte sheet.
  class ExportForm150Xlsx
    SOPORTE_SHEET = "Soporte ventas"
    FORM_SHEET = "Formulario 150"

    RUBRO_VENTAS_13 = "Ventas a 13%"
    RUBRO_EXENTAS = "Exentas crédito pleno"

    SOPORTE_HEADERS = [
      "Fecha pago", "Método", "Moneda", "Subtotal", "IVA 13%", "Total cobrado",
      "Referencia", "Email", "Estado", "ID", "Rubro Form 150"
    ].freeze

    CASILLA_VENTAS_13 = "Total ventas a 13%"
    CASILLA_IMPUESTO_13 = "Monto de impuesto a 13%"
    CASILLA_EXENTAS = "Total ventas exentas con derecho a crédito pleno"
    CASILLA_VENTAS_GRAVADAS = "Total ventas generales gravadas"
    CASILLA_MONTO_IMPUESTO = "Monto impuesto"

    FORM_FOOTNOTE = "Copiar montos a TRIBU-CR Formulario 150 (IVA01). Compras y crédito fiscal: completar en portal."

    DATA_ROW_START = 2
    DATA_ROW_END = 5000

    def self.call(payments, start_date:, end_date:, direction: "desc")
      raise ArgumentError, "start_date required" if start_date.blank?
      raise ArgumentError, "end_date required" if end_date.blank?

      package = Axlsx::Package.new
      wb = package.workbook
      styles = ExportPaymentsXlsx.send(:build_styles, wb)

      add_soporte_sheet(wb, payments, direction:, styles:)
      add_formulario_sheet(wb, start_date:, end_date:, styles:)

      package.to_stream.read
    end

    def self.add_soporte_sheet(wb, payments, direction:, styles:)
      sorted = payments.order(paid_at: direction.to_sym, id: direction.to_sym)

      wb.add_worksheet(name: SOPORTE_SHEET) do |sheet|
        sheet.add_row SOPORTE_HEADERS, style: styles.fetch(:header), height: 32

        sorted.each_with_index do |payment, idx|
          stripe = idx.odd?
          row_plain = stripe ? styles.fetch(:stripe) : styles.fetch(:plain)
          row_money = stripe ? styles.fetch(:money_stripe) : styles.fetch(:money)
          row_date = stripe ? styles.fetch(:date_stripe) : styles.fetch(:date)

          sheet.add_row(
            soporte_row_values(payment),
            types: soporte_row_types,
            style: soporte_row_styles(row_plain, row_date, row_money),
            height: 20
          )
        end

        sheet.column_widths 16, 14, 8, 12, 12, 12, 16, 28, 12, 8, 22
        sheet.sheet_view.show_grid_lines = true
      end
    end
    private_class_method :add_soporte_sheet

    def self.add_formulario_sheet(wb, start_date:, end_date:, styles:)
      wb.add_worksheet(name: FORM_SHEET) do |sheet|
        sheet.escape_formulas = false

        sheet.add_row [ "Formulario 150 — Impuesto al Valor Agregado (IVA01)" ], style: styles.fetch(:header)
        sheet.add_row [ "Período", "#{start_date} — #{end_date}" ], style: styles.fetch(:plain)
        sheet.add_row [ "Cédula", "" ], style: styles.fetch(:plain)
        sheet.add_row [ "Nombre", "" ], style: styles.fetch(:plain)
        sheet.add_row []

        sheet.add_row [ "Casilla", "Monto", "Moneda", "Notas" ], style: styles.fetch(:summary_header), height: 28
        add_formulario_casilla_rows(sheet, styles)

        sheet.add_row []
        sheet.add_row [ FORM_FOOTNOTE ], style: styles.fetch(:plain)

        sheet.column_widths 48, 16, 10, 40
        sheet.sheet_view.show_grid_lines = true
      end
    end
    private_class_method :add_formulario_sheet

    def self.add_formulario_casilla_rows(sheet, styles)
      casillas = [
        [ CASILLA_VENTAS_13, sumifs_subtotal(RUBRO_VENTAS_13), "CRC", "Sección I" ],
        [ CASILLA_IMPUESTO_13, sumifs_iva(RUBRO_VENTAS_13), "CRC", "Sección I" ],
        [ CASILLA_EXENTAS, sumifs_subtotal(RUBRO_EXENTAS), "USD", "Sección I — exportación servicios" ],
        [ CASILLA_VENTAS_GRAVADAS, sumifs_subtotal(RUBRO_VENTAS_13), "CRC", "Sección I" ],
        [ CASILLA_MONTO_IMPUESTO, sumifs_iva(RUBRO_VENTAS_13), "CRC", "Sección I" ]
      ]

      casillas.each do |label, formula, currency, notes|
        sheet.add_row(
          [ label, formula, currency, notes ],
          types: [ :string, :string, :string, :string ],
          style: [ styles.fetch(:plain), styles.fetch(:money), styles.fetch(:plain), styles.fetch(:plain) ],
          escape_formulas: [ true, false, true, true ],
          height: 20
        )
      end
    end
    private_class_method :add_formulario_casilla_rows

    def self.sumifs_subtotal(rubro)
      "=SUMIFS('#{SOPORTE_SHEET}'!D#{DATA_ROW_START}:D#{DATA_ROW_END},'#{SOPORTE_SHEET}'!K#{DATA_ROW_START}:K#{DATA_ROW_END},\"#{rubro}\")"
    end
    private_class_method :sumifs_subtotal

    def self.sumifs_iva(rubro)
      "=SUMIFS('#{SOPORTE_SHEET}'!E#{DATA_ROW_START}:E#{DATA_ROW_END},'#{SOPORTE_SHEET}'!K#{DATA_ROW_START}:K#{DATA_ROW_END},\"#{rubro}\")"
    end
    private_class_method :sumifs_iva

    def self.soporte_row_values(payment)
      paid_at = payment.paid_at&.in_time_zone(HaciendaSummaryRows::CR_ZONE)
      [
        paid_at,
        PaymentDisplayLabels.payment_method_label(payment.payment_method),
        payment.currency.to_s.upcase,
        payment.subtotal.to_f,
        payment.tax_amount.to_f,
        HaciendaSummaryRows.net_collected(payment),
        payment.purchase_reference.to_s,
        payment.purchaser_email.to_s,
        PaymentDisplayLabels.status_label(payment.status),
        payment.id.to_s,
        rubro_for(payment)
      ]
    end
    private_class_method :soporte_row_values

    def self.rubro_for(payment)
      payment.currency.to_s == "usd" ? RUBRO_EXENTAS : RUBRO_VENTAS_13
    end
    private_class_method :rubro_for

    def self.soporte_row_types
      [ nil, :string, :string, :float, :float, :float, :string, :string, :string, :string, :string ]
    end
    private_class_method :soporte_row_types

    def self.soporte_row_styles(row_plain, row_date, row_money)
      [
        row_date, row_plain, row_plain, row_money, row_money, row_money,
        row_plain, row_plain, row_plain, row_plain, row_plain
      ]
    end
    private_class_method :soporte_row_styles
  end
end
