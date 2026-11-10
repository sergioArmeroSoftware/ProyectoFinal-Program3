# Especificaciones de estructura del código

Esta guía define las convenciones para organizar y escribir el código del
proyecto en Elixir. Su objetivo es mantener los programas claros, reutilizables
y fáciles de probar.

## 1. Estilo de programación

- Utilizar **programación funcional**: transformar datos mediante funciones y
  evitar modificar estado compartido.
- Preferir valores inmutables y crear nuevos valores al transformar listas,
  mapas u otras colecciones.
- Mantener la entrada y salida (teclado, pantalla y archivos) en los límites del
  programa. Las funciones de cálculo y transformación deben trabajar, siempre
  que sea posible, sin efectos secundarios.
- Resolver decisiones mediante pattern matching y guardas cuando esto haga el
  comportamiento más explícito.

## 2. Módulos y responsabilidades

- Cada módulo debe tener una responsabilidad clara y relacionada con su nombre.
- Agrupar en módulos separados la coordinación del programa, las reglas del
  dominio, las validaciones, los reportes y las funciones auxiliares cuando el
  tamaño del programa lo justifique.
- Usar nombres de módulos en `PascalCase`, por ejemplo `Liquidacion` o
  `DatosLogicos`.
- Mantener el punto de entrada en una función `main/0` cuando el programa
  necesite coordinar varios pasos.
- Evitar que módulos de lógica impriman directamente resultados si existe un
  módulo de entrada/salida encargado de hacerlo.

## 3. Funciones pequeñas y atómicas

- Dividir el comportamiento en funciones pequeñas; cada función debe realizar
  una tarea concreta y coherente.
- Una función debe recibir los datos que necesita y devolver su resultado, sin
  depender de estado oculto.
- Separar pasos distinguibles, por ejemplo: leer una entrada, validarla,
  calcular un resultado y construir el mensaje que se presentará.
- Extraer la lógica repetida a una función reutilizable en vez de copiarla.
- Mantener los detalles internos como funciones privadas (`defp`) y exponer
  solamente las funciones que otros módulos necesitan utilizar.
- Usar cláusulas de una misma función para representar casos alternativos
  claros, especialmente con pattern matching y guardas.

## 4. Nombres

- Escribir nombres de funciones y variables en `snake_case`.
- Nombrar las funciones con **verbos** que describan la acción o transformación:
  `calcular_total/2`, `validar_servicio/3`, `generar_mensaje/1` o
  `mostrar_resultado/1`.
- Nombrar las funciones predicado con `?` al final y hacer que retornen un
  booleano, por ejemplo `hay_promocion?/2`.
- Nombrar las variables con sustantivos descriptivos, por ejemplo
  `servicios_validos` en lugar de `x`.
- Preferir nombres explícitos sobre abreviaturas que no sean conocidas en el
  dominio.

## 5. Uso de pipelines

- Usar el operador `|>` cuando un valor pasa por una secuencia lineal de
  transformaciones. El valor inicial debe ser el primer argumento de la función
  siguiente.
- Mantener cada etapa del pipeline legible y en el orden en que se ejecuta.
- Usar argumentos adicionales después del valor canalizado, como en
  `Util.ingresar(:entero)`.
- Evitar pipelines cuando dificulten entender el flujo, cuando haya varias
  entradas principales o cuando la operación requiera ramificaciones
  complejas. En esos casos, asignar resultados a variables descriptivas o usar
  `case`.

```elixir
"Ingrese su edad: "
|> Util.ingresar(:entero)
|> calcular_categoria()
|> generar_mensaje()
|> Util.mostrar_mensaje()
```

## 6. Datos, errores y validaciones

- Pasar explícitamente a las funciones los datos que necesitan; evitar
  dependencias implícitas.
- Para operaciones que pueden fallar, representar el resultado de forma clara,
  por ejemplo con `{:ok, resultado}` y `{:error, motivo}`, y manejar ambos casos
  en el punto correspondiente.
- Validar los datos antes de aplicar cálculos que dependan de su validez.
- No ocultar errores ni reemplazarlos silenciosamente por valores que parezcan
  válidos.
- Mantener los mensajes de error comprensibles y, cuando corresponda, dirigirlos
  a la salida estándar de errores.

## 7. Documentación y formato

- Agregar `@moduledoc` cuando el propósito del módulo necesite explicación.
- Documentar las funciones públicas con `@doc`, indicando su propósito,
  parámetros, resultado y ejemplos útiles.
- Aplicar formato consistente con el formato estándar de Elixir: indentación de
  dos espacios y líneas organizadas para facilitar la lectura.
- Usar comentarios para explicar decisiones o contexto que no sean evidentes;
  no repetir en comentarios lo que el código ya expresa claramente.

## 8. Ejecución y organización de scripts

- Mantener las funciones y módulos reutilizables en archivos compilables
  (`.ex`), agrupados según su responsabilidad. Por ejemplo, las funciones de
  validación deben estar en un módulo de validación y las operaciones comunes
  de entrada/salida en un módulo de utilidades.
- Diseñar las funciones de esos módulos para que puedan invocarse desde distintos
  scripts o módulos, recibiendo sus datos como argumentos y devolviendo
  resultados. Evitar duplicar una función en varios archivos: extraerla al
  módulo común que corresponda y reutilizarla mediante el nombre del módulo.
- Mantener los archivos de script (`.exs`) para cargar datos, coordinar el flujo
  de la aplicación y ejecutar el punto de entrada; no usarlos como ubicación
  principal de lógica que deba compartirse.
- Evitar ejecutar lógica de aplicación como efecto de compilar un módulo
  reutilizable. Colocar la llamada al punto de entrada, como
  `Programa.main()`, en el script ejecutable correspondiente.
- Compilar los módulos `.ex` antes de ejecutar el script que los utiliza y
  configurar la ruta de carga para que el ejecutable pueda encontrarlos. Por
  ejemplo:

  ```powershell
  elixirc *.ex
  elixir -pa . programa.exs
  ```
