# claude-orquesta

![pruebas](https://github.com/<tu-usuario>/claude-orquesta/actions/workflows/tests.yml/badge.svg)

Plugin de Claude Code. **orquesta**: Claude Fable/Opus como arquitecto que clarifica, diseña y revisa; subagentes con el modelo que vos configurás que implementan; compuertas en PowerShell 7 que hacen cumplir el protocolo.

```
/plugin marketplace add <tu-usuario>/claude-orquesta
/plugin install orquesta@orquesta
```

Documentación completa, configuración de modelos y compuertas: [`plugins/orquesta/README.md`](plugins/orquesta/README.md).

Pruebas: `pwsh -NoProfile -File plugins/orquesta/tests/Test-Orquesta.ps1`

Para agregar otro plugin al marketplace: carpeta en `plugins/<nombre>/` con su `.claude-plugin/plugin.json` y una entrada en `.claude-plugin/marketplace.json`.
