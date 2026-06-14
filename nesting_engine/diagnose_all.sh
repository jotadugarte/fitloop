#!/bin/bash
# Script para correr el diagnóstico en todos los archivos DXF de la carpeta individuals

for file in nesting_engine/tests/fixtures/individuals/*.dxf; do
    echo "================================================================================"
    echo "Procesando: $file"
    echo "================================================================================"
    .venv/bin/python nesting_engine/diagnose_dxf.py "$file" --primary CORTE
    echo ""
done
