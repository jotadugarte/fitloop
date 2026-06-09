<task_session>
  <metadata>
    <task_name>Habilitar RSpec y Cobertura 100% en CI</task_name>
    <type>Chore</type>
    <req_id>[REQ-FIT-QA-001](file:///home/jader/proyectos/fitloop/docs/core/SPEC.md)</req_id>
    <roadmap_item>1. Pruebas, Calidad & Cobertura (CI/CD)</roadmap_item>
  </metadata>

  <implementation_plan>
    <step id="1" status="complete">Ejecutar las pruebas existentes localmente para establecer una línea base verde (green baseline)</step>
    <step id="2" status="complete">Agregar la gema 'simplecov' al Gemfile en el grupo de :test</step>
    <step id="3" status="complete">Configurar SimpleCov en spec/rails_helper.rb (o spec_helper.rb) para requerir una cobertura del 100%</step>
    <step id="4" status="complete">Ejecutar la suite localmente para verificar que se genere el reporte de SimpleCov e identificar archivos faltantes de cobertura</step>
    <step id="5" status="complete">Modificar .github/workflows/ci.yml agregando el job 'rspec' con un servicio PostgreSQL y configurando el entorno híbrido (Ruby + Python + cmake + libboost-dev + pip requirements)</step>
    <step id="6" status="pending">Correr el CI y resolver cualquier fallo en la ejecución o en la base de datos de pruebas</step>
    <step id="7" status="pending">Agregar los specs que hagan falta para alcanzar el 100% de cobertura de código requerida y asegurar el paso exitoso del CI</step>
  </implementation_plan>

  <working_notes>
    - El job de RSpec requiere levantar un servicio de PostgreSQL de prueba.
    - Debido a que las pruebas del sistema ejecutan el CLI de Python de nesting_engine de manera real (inline), el entorno de RSpec en CI también debe tener Python y todas las dependencias del motor anidador instaladas.
    - Se agregará SimpleCov al proyecto.
  </working_notes>
</task_session>
