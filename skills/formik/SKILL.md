---
name: formik
description: Formik v2 patterns for form management including Formik component, useFormik hook, Field, FieldArray, Yup validation, and MUI integration.
user-invocable: true
---

# Formik v2 Patterns

## Quick Start — Formik + Yup

```typescript
import { Formik, Form, Field, ErrorMessage } from 'formik';
import * as Yup from 'yup';

interface LoginValues { email: string; password: string }

const schema = Yup.object({
  email: Yup.string().email('Invalid email').required('Required'),
  password: Yup.string().min(8, 'Too short').required('Required'),
});

function LoginForm() {
  return (
    <Formik<LoginValues>
      initialValues={{ email: '', password: '' }}
      validationSchema={schema}
      onSubmit={(values, { setSubmitting }) => {
        submitLogin(values).finally(() => setSubmitting(false));
      }}
    >
      {({ isSubmitting }) => (
        <Form>
          <Field name="email" type="email" />
          <ErrorMessage name="email" component="div" />
          <Field name="password" type="password" />
          <ErrorMessage name="password" component="div" />
          <button type="submit" disabled={isSubmitting}>Log In</button>
        </Form>
      )}
    </Formik>
  );
}
```

## Core Rules

- DO prefer `<Formik>` component over `useFormik` — it creates context for Field/FieldArray/ErrorMessage
- DO always type: `<Formik<MyValues> initialValues={...} onSubmit={...}>`
- DO check `touched` before showing errors: `{touched.email && errors.email && <div>{errors.email}</div>}`
- DO use Yup for schema validation via `validationSchema` prop
- DO NOT use `useFormik` unless you need full manual control (no Field/FieldArray support)

## useFormik Caveat

`useFormik` does NOT create Formik context. `<Field>`, `<FieldArray>`, and `<ErrorMessage>` will NOT work. You must wire inputs manually. Use `getFieldProps` shorthand:

```typescript
const formik = useFormik<MyValues>({ initialValues, validationSchema, onSubmit });
<input {...formik.getFieldProps('fieldName')} />
```

## Yup Validation

```typescript
const schema = Yup.object({
  username: Yup.string().min(3).max(20).matches(/^[a-zA-Z0-9_]+$/).required(),
  email: Yup.string().email().required(),
  password: Yup.string().min(8).matches(/[A-Z]/).matches(/[0-9]/).required(),
  confirmPassword: Yup.string().oneOf([Yup.ref('password')], 'Must match').required(),
  age: Yup.number().min(18).max(120).required(),
  acceptTerms: Yup.boolean().oneOf([true], 'Must accept'),
});
```

> See `resources/validation-patterns.md` for conditional, cross-field, custom test, and async validation.

## MUI Integration

Wire Formik → MUI TextField with this pattern:

```typescript
<TextField
  name="fieldName"
  label="Label"
  value={values.fieldName}
  onChange={handleChange}
  onBlur={handleBlur}
  error={touched.fieldName && !!errors.fieldName}
  helperText={touched.fieldName && errors.fieldName}
  fullWidth
/>
```

> See `resources/mui-integration.md` for Select, Checkbox, Autocomplete, DatePicker, and reusable wrappers.

## FieldArray

```typescript
<FieldArray name="items">
  {({ push, remove }) => (
    <div>
      {values.items.map((_, i) => (
        <div key={i}>
          <Field name={`items.${i}.name`} />
          <button type="button" onClick={() => remove(i)}>Remove</button>
        </div>
      ))}
      <button type="button" onClick={() => push({ name: '' })}>Add</button>
      {typeof errors.items === 'string' && <div>{errors.items}</div>}
    </div>
  )}
</FieldArray>
```

- DO check `typeof errors.items === 'string'` for array-level errors
- DO NOT render `errors.items` directly — may be `[object Object]`

## Async Submission

```typescript
onSubmit={async (values, { setSubmitting, setFieldError, setErrors }) => {
  try {
    await api.submit(values);
  } catch (error) {
    if (error.status === 409) setFieldError('email', 'Already registered');
    else setErrors(error.validationErrors);
  } finally {
    setSubmitting(false);
  }
}}
```

## enableReinitialize

Use when `initialValues` come from async data (API). Resets `dirty`, `touched`, `errors` on change. User edits are lost when initialValues update.

```typescript
<Formik enableReinitialize initialValues={dataFromApi} ...>
```

## Validation Timing

```typescript
<Formik
  validateOnChange={true}   // default: validate on keystroke
  validateOnBlur={true}     // default: validate on blur
  validateOnMount={false}   // default: no validate on mount
>
```

For expensive validation: `validateOnChange={false}` to validate only on blur/submit.

## References

- `resources/validation-patterns.md` — advanced Yup: conditional, cross-field, async
- `resources/mui-integration.md` — MUI + Formik wiring for all component types
