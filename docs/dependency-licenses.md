# Dependency licenses

The `0.1.0` release manifest has eight direct Ada library dependencies. The versions validated in the development
workspace and their declared licenses are:

| Crate | Validated version | Release constraint | Declared license |
| --- | ---: | ---: | --- |
| database | 0.14.0 | `^0.14.0` | MIT |
| ada_quality | 0.1.0 | `^0.1.0` | MIT |
| jsonlib | 0.1.0-dev | `^0.1.0` | MIT |
| messages | 0.1.0 | `^0.1.0` | MIT |
| terminal_styles | 0.1.0-dev | `^0.1.0` | MIT |
| project_tools | 0.1.0 | `^0.1.0` | MIT |
| hostkit | 0.1.0-dev | `^0.1.0` | MIT |
| model_runner | 0.1.0-dev | `^0.1.0` | MIT |

`gnat_native =15.2.1` is the compiler toolchain dependency rather than an application library. Transitive dependency
licenses remain the responsibility of their direct parent crates and the selected Alire solution. Publication must not
proceed until the pin-free manifest resolves and Alire's generated solution has been reviewed.
