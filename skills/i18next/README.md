# i18next Skill

Internationalization with i18next v21+ and react-i18next v11 for React/TypeScript.

## When to Use

- Adding or modifying translations
- Handling pluralization (v21: `_one`/`_other`)
- Working with interpolation (`{{variable}}`)
- Using Trans component for JSX in translations
- Configuring language detection or switching
- Organizing translations with namespaces
- Adding TypeScript types for translation keys

## Key Conventions

- Import: `import { useTranslation } from 'react-i18next'`
- Non-suspense: always handle `ready` state
- Plurals: `_one`/`_other` (NOT `_plural`)
- Interpolation: `{{variable}}` double curly braces

## Resources

- `resources/translation-patterns.md` — interpolation, plural, context patterns
- `resources/setup-guide.md` — init config, detection, namespaces, TypeScript setup
