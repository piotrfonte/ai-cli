# Yup Validation Patterns

Advanced Yup validation patterns for use with Formik's `validationSchema` prop.

---

## Yup Schema Basics

### String Validation

```typescript
import * as Yup from 'yup';

const stringSchema = Yup.object({
  // Basic string
  name: Yup.string()
    .required('Name is required'),

  // Email
  email: Yup.string()
    .email('Invalid email address')
    .required('Email is required'),

  // URL
  website: Yup.string()
    .url('Invalid URL')
    .notRequired(),

  // Pattern matching
  slug: Yup.string()
    .matches(/^[a-z0-9-]+$/, 'Only lowercase letters, numbers, and hyphens')
    .required('Slug is required'),

  // Length constraints
  username: Yup.string()
    .min(3, 'Must be at least 3 characters')
    .max(20, 'Must be 20 characters or less')
    .required('Username is required'),

  // Trimmed string
  title: Yup.string()
    .trim('Cannot have leading/trailing spaces')
    .strict(true)
    .required('Title is required'),

  // One of specific values
  role: Yup.string()
    .oneOf(['admin', 'editor', 'viewer'], 'Invalid role')
    .required('Role is required'),
});
```

### Number Validation

```typescript
const numberSchema = Yup.object({
  // Basic number
  age: Yup.number()
    .integer('Must be a whole number')
    .min(0, 'Must be positive')
    .max(150, 'Invalid age')
    .required('Age is required'),

  // Price with precision
  price: Yup.number()
    .positive('Must be positive')
    .test(
      'max-decimals',
      'Maximum 2 decimal places',
      (value) => value === undefined || /^\d+(\.\d{1,2})?$/.test(String(value)),
    )
    .required('Price is required'),

  // Percentage
  discount: Yup.number()
    .min(0, 'Cannot be negative')
    .max(100, 'Cannot exceed 100%')
    .required('Discount is required'),

  // Quantity (positive integer)
  quantity: Yup.number()
    .integer('Must be a whole number')
    .min(1, 'Must be at least 1')
    .required('Quantity is required'),
});
```

### Boolean Validation

```typescript
const booleanSchema = Yup.object({
  // Must be true (e.g., accept terms)
  acceptTerms: Yup.boolean()
    .oneOf([true], 'You must accept the terms and conditions')
    .required('Required'),

  // Optional boolean
  newsletter: Yup.boolean()
    .default(false),
});
```

### Date Validation

```typescript
const dateSchema = Yup.object({
  // Basic date
  birthDate: Yup.date()
    .max(new Date(), 'Cannot be in the future')
    .required('Birth date is required'),

  // Date range
  startDate: Yup.date()
    .min(new Date(), 'Must be in the future')
    .required('Start date is required'),

  endDate: Yup.date()
    .min(Yup.ref('startDate'), 'End date must be after start date')
    .required('End date is required'),
});
```

### Mixed Type

```typescript
const mixedSchema = Yup.object({
  // File upload
  avatar: Yup.mixed<File>()
    .test('fileSize', 'File too large (max 5MB)', (value) => {
      if (!value) return true;
      return value.size <= 5 * 1024 * 1024;
    })
    .test('fileType', 'Unsupported format', (value) => {
      if (!value) return true;
      return ['image/jpeg', 'image/png', 'image/webp'].includes(value.type);
    }),

  // Nullable field
  middleName: Yup.string().nullable().notRequired(),
});
```

---

## Array Validation

```typescript
const arraySchema = Yup.object({
  // Array of strings
  tags: Yup.array()
    .of(Yup.string().required('Tag cannot be empty'))
    .min(1, 'At least one tag is required')
    .max(10, 'Maximum 10 tags'),

  // Array of objects
  addresses: Yup.array()
    .of(
      Yup.object({
        street: Yup.string().required('Street is required'),
        city: Yup.string().required('City is required'),
        state: Yup.string().required('State is required'),
        zip: Yup.string()
          .matches(/^\d{5}(-\d{4})?$/, 'Invalid ZIP code')
          .required('ZIP is required'),
      }),
    )
    .min(1, 'At least one address is required'),

  // Unique items
  emails: Yup.array()
    .of(Yup.string().email('Invalid email').required('Required'))
    .test('unique', 'Emails must be unique', (values) => {
      if (!values) return true;
      return new Set(values).size === values.length;
    }),
});
```

---

## Nested Object Validation

```typescript
const nestedSchema = Yup.object({
  name: Yup.string().required('Required'),

  // Nested object
  address: Yup.object({
    street: Yup.string().required('Street is required'),
    city: Yup.string().required('City is required'),
    state: Yup.string().required('State is required'),
    zip: Yup.string().required('ZIP is required'),
  }).required('Address is required'),

  // Deeply nested
  company: Yup.object({
    name: Yup.string().required('Company name is required'),
    address: Yup.object({
      street: Yup.string().required('Street is required'),
      city: Yup.string().required('City is required'),
    }),
  }),
});
```

Use dot notation in Formik Field names to match nested schemas:

```typescript
<Field name="address.street" placeholder="Street" />
<Field name="company.address.city" placeholder="City" />
```

---

## Conditional Validation with .when()

Validate fields based on other field values.

### Basic Conditional

```typescript
const conditionalSchema = Yup.object({
  contactMethod: Yup.string()
    .oneOf(['email', 'phone'])
    .required('Required'),

  email: Yup.string().when('contactMethod', {
    is: 'email',
    then: (schema) => schema.email('Invalid email').required('Email is required'),
    otherwise: (schema) => schema.notRequired(),
  }),

  phone: Yup.string().when('contactMethod', {
    is: 'phone',
    then: (schema) =>
      schema
        .matches(/^\+?[\d\s-()]+$/, 'Invalid phone number')
        .required('Phone is required'),
    otherwise: (schema) => schema.notRequired(),
  }),
});
```

### Multiple Dependencies

```typescript
const multiDepSchema = Yup.object({
  country: Yup.string().required('Required'),
  hasState: Yup.boolean(),

  state: Yup.string().when(['country', 'hasState'], {
    is: (country: string, hasState: boolean) =>
      country === 'US' && hasState === true,
    then: (schema) => schema.required('State is required for US addresses'),
    otherwise: (schema) => schema.notRequired(),
  }),
});
```

### Conditional with Function

```typescript
const functionConditional = Yup.object({
  employmentType: Yup.string().required('Required'),

  salary: Yup.number().when('employmentType', {
    is: (val: string) => val === 'full-time' || val === 'part-time',
    then: (schema) => schema.positive('Must be positive').required('Salary is required'),
    otherwise: (schema) => schema.notRequired(),
  }),

  hourlyRate: Yup.number().when('employmentType', {
    is: 'contractor',
    then: (schema) =>
      schema
        .positive('Must be positive')
        .max(500, 'Rate seems too high')
        .required('Hourly rate is required'),
    otherwise: (schema) => schema.notRequired(),
  }),
});
```

---

## Cross-Field Validation with Yup.ref()

Reference other field values within validation rules.

### Password Confirmation

```typescript
const passwordSchema = Yup.object({
  password: Yup.string()
    .min(8, 'Must be at least 8 characters')
    .matches(/[A-Z]/, 'Must contain an uppercase letter')
    .matches(/[a-z]/, 'Must contain a lowercase letter')
    .matches(/[0-9]/, 'Must contain a number')
    .matches(/[^a-zA-Z0-9]/, 'Must contain a special character')
    .required('Password is required'),

  confirmPassword: Yup.string()
    .oneOf([Yup.ref('password')], 'Passwords must match')
    .required('Please confirm your password'),
});
```

### Date Range

```typescript
const dateRangeSchema = Yup.object({
  startDate: Yup.date()
    .required('Start date is required'),

  endDate: Yup.date()
    .min(Yup.ref('startDate'), 'End date must be after start date')
    .required('End date is required'),
});
```

### Numeric Comparison

```typescript
const priceRangeSchema = Yup.object({
  minPrice: Yup.number()
    .min(0, 'Cannot be negative')
    .required('Min price is required'),

  maxPrice: Yup.number()
    .min(Yup.ref('minPrice'), 'Max must be greater than min')
    .required('Max price is required'),
});
```

---

## Custom .test() Validators

### Synchronous Custom Test

```typescript
const customTestSchema = Yup.object({
  // Custom test with test() method
  creditCard: Yup.string()
    .test('luhn', 'Invalid credit card number', (value) => {
      if (!value) return true;
      const digits = value.replace(/\D/g, '');
      if (digits.length < 13 || digits.length > 19) return false;

      let sum = 0;
      let alternate = false;
      for (let i = digits.length - 1; i >= 0; i--) {
        let n = parseInt(digits[i], 10);
        if (alternate) {
          n *= 2;
          if (n > 9) n -= 9;
        }
        sum += n;
        alternate = !alternate;
      }
      return sum % 10 === 0;
    })
    .required('Credit card is required'),

  // Custom test accessing parent context
  passwordConfirm: Yup.string()
    .test('match', 'Passwords must match', function (value) {
      // Use function() (not arrow) to access this.parent
      return value === this.parent.password;
    })
    .required('Required'),
});
```

### Custom Test with createError

```typescript
const advancedTestSchema = Yup.object({
  username: Yup.string()
    .test('no-reserved', 'Username check failed', function (value) {
      if (!value) return true;
      const reserved = ['admin', 'root', 'system', 'moderator'];
      if (reserved.includes(value.toLowerCase())) {
        return this.createError({
          message: `"${value}" is a reserved username`,
          path: this.path,
        });
      }
      return true;
    })
    .required('Required'),
});
```

---

## Async Validation

### Async Custom Test (e.g., Check Username Availability)

```typescript
const asyncSchema = Yup.object({
  username: Yup.string()
    .min(3, 'Too short')
    .max(20, 'Too long')
    .test(
      'username-available',
      'Username is already taken',
      async (value) => {
        if (!value || value.length < 3) return true; // Skip if too short
        try {
          const response = await fetch(`/api/check-username?q=${value}`);
          const data = await response.json();
          return data.available;
        } catch {
          return true; // Allow on network error, server will validate
        }
      },
    )
    .required('Username is required'),

  email: Yup.string()
    .email('Invalid email')
    .test(
      'email-available',
      'Email is already registered',
      async (value) => {
        if (!value) return true;
        try {
          const response = await fetch(`/api/check-email?q=${value}`);
          const data = await response.json();
          return !data.exists;
        } catch {
          return true;
        }
      },
    )
    .required('Email is required'),
});
```

### Debouncing Async Validation

Formik does not debounce validation by default. For async field-level validators, implement debouncing yourself:

```typescript
import { debounce } from 'lodash-es';

const checkUsername = debounce(
  async (value: string, resolve: (error: string | undefined) => void) => {
    if (!value || value.length < 3) {
      resolve(undefined);
      return;
    }
    try {
      const res = await fetch(`/api/check-username?q=${value}`);
      const data = await res.json();
      resolve(data.available ? undefined : 'Username is taken');
    } catch {
      resolve(undefined);
    }
  },
  300,
);

function validateUsername(value: string): Promise<string | undefined> {
  return new Promise((resolve) => {
    checkUsername(value, resolve);
  });
}

// Use as field-level validator
<Field name="username" validate={validateUsername} />
```

---

## Error Message Customization

### Per-Field Messages

```typescript
const schema = Yup.object({
  email: Yup.string()
    .email('Please enter a valid email address')
    .required('We need your email to continue'),

  age: Yup.number()
    .typeError('Age must be a number')       // When input is not a number
    .min(18, 'You must be at least 18')
    .max(120, 'Please enter a valid age')
    .required('Age is required'),
});
```

### Dynamic Messages with Template Functions

```typescript
const schema = Yup.object({
  password: Yup.string()
    .min(8, ({ min }) => `Password must be at least ${min} characters`)
    .max(128, ({ max }) => `Password cannot exceed ${max} characters`)
    .required('Password is required'),

  items: Yup.array()
    .min(1, ({ min }) => `You need at least ${min} item`)
    .max(50, ({ max }) => `You can have at most ${max} items`),
});
```

### Setting Default Messages

```typescript
import { setLocale } from 'yup';

setLocale({
  mixed: {
    required: 'This field is required',
    notType: 'Invalid value',
  },
  string: {
    email: 'Please enter a valid email',
    min: ({ min }) => `Must be at least ${min} characters`,
    max: ({ max }) => `Must be at most ${max} characters`,
  },
  number: {
    min: ({ min }) => `Must be at least ${min}`,
    max: ({ max }) => `Must be at most ${max}`,
    positive: 'Must be a positive number',
    integer: 'Must be a whole number',
  },
});
```

---

## Complete Example: Registration Form Schema

```typescript
import * as Yup from 'yup';

export const registrationSchema = Yup.object({
  // Personal info
  firstName: Yup.string()
    .trim()
    .min(1, 'Required')
    .max(50, 'Too long')
    .required('First name is required'),

  lastName: Yup.string()
    .trim()
    .min(1, 'Required')
    .max(50, 'Too long')
    .required('Last name is required'),

  email: Yup.string()
    .email('Invalid email address')
    .required('Email is required'),

  // Password with cross-field ref
  password: Yup.string()
    .min(8, 'Must be at least 8 characters')
    .matches(/[A-Z]/, 'Needs an uppercase letter')
    .matches(/[0-9]/, 'Needs a number')
    .required('Password is required'),

  confirmPassword: Yup.string()
    .oneOf([Yup.ref('password')], 'Passwords must match')
    .required('Please confirm your password'),

  // Conditional validation
  accountType: Yup.string()
    .oneOf(['personal', 'business'])
    .required('Required'),

  companyName: Yup.string().when('accountType', {
    is: 'business',
    then: (schema) => schema.required('Company name is required for business accounts'),
    otherwise: (schema) => schema.notRequired(),
  }),

  taxId: Yup.string().when('accountType', {
    is: 'business',
    then: (schema) =>
      schema
        .matches(/^\d{2}-\d{7}$/, 'Format: XX-XXXXXXX')
        .required('Tax ID is required for business accounts'),
    otherwise: (schema) => schema.notRequired(),
  }),

  // Array validation
  interests: Yup.array()
    .of(Yup.string().required())
    .min(1, 'Select at least one interest')
    .max(5, 'Maximum 5 interests'),

  // Boolean
  acceptTerms: Yup.boolean()
    .oneOf([true], 'You must accept the terms')
    .required('Required'),

  // Nested object
  address: Yup.object({
    street: Yup.string().required('Street is required'),
    city: Yup.string().required('City is required'),
    state: Yup.string().required('State is required'),
    zip: Yup.string()
      .matches(/^\d{5}(-\d{4})?$/, 'Invalid ZIP code')
      .required('ZIP is required'),
  }),
});

export type RegistrationValues = Yup.InferType<typeof registrationSchema>;
```

### Using InferType

Yup can infer the TypeScript type from a schema, keeping your type and validation in sync:

```typescript
const schema = Yup.object({
  name: Yup.string().required(),
  age: Yup.number().required(),
  active: Yup.boolean().default(false),
});

type FormValues = Yup.InferType<typeof schema>;
// { name: string; age: number; active: boolean }
```

---

---

## Displaced Patterns from SKILL.md

### Formik Render Props Reference

| Prop | Type | Description |
|------|------|-------------|
| `values` | `Values` | Current form values |
| `errors` | `FormikErrors<Values>` | Validation errors |
| `touched` | `FormikTouched<Values>` | Fields that have been visited |
| `isSubmitting` | `boolean` | Whether form is submitting |
| `isValid` | `boolean` | Whether form has no errors |
| `dirty` | `boolean` | Whether values differ from initial |
| `handleChange` | `(e: ChangeEvent) => void` | Change handler |
| `handleBlur` | `(e: FocusEvent) => void` | Blur handler |
| `handleSubmit` | `(e: FormEvent) => void` | Submit handler |
| `setFieldValue` | `(field, value) => void` | Set a field value |
| `setFieldTouched` | `(field, touched) => void` | Set touched |
| `setErrors` | `(errors) => void` | Set all errors |
| `setFieldError` | `(field, error) => void` | Set a single field error |
| `resetForm` | `(nextState?) => void` | Reset the form |
| `setSubmitting` | `(isSubmitting) => void` | Set submitting state |
| `validateForm` | `() => Promise<errors>` | Trigger validation |
| `validateField` | `(field) => void` | Trigger field validation |

### FieldArray Helpers Reference

| Helper | Signature | Description |
|--------|-----------|-------------|
| `push` | `(value) => void` | Add to end |
| `remove` | `(index) => any` | Remove at index |
| `insert` | `(index, value) => void` | Insert at index |
| `swap` | `(a, b) => void` | Swap two items |
| `move` | `(from, to) => void` | Move item |
| `unshift` | `(value) => number` | Add to beginning |
| `replace` | `(index, value) => void` | Replace at index |
| `pop` | `() => any` | Remove last |

### Field-Level Validation

```typescript
function validateUsername(value: string): string | undefined {
  if (!value) return 'Required';
  if (value.length < 3) return 'Too short';
  if (!/^[a-zA-Z0-9_]+$/.test(value)) return 'Invalid characters';
  return undefined;
}

async function validateEmailAvailable(value: string): Promise<string | undefined> {
  if (!value) return 'Required';
  const taken = await checkEmailExists(value);
  if (taken) return 'Email is already in use';
  return undefined;
}

<Field name="username" validate={validateUsername} />
<Field name="email" validate={validateEmailAvailable} />
```

### FormikProvider Pattern

```typescript
import { useFormik, FormikProvider, Form, Field } from 'formik';

function MultiStepForm() {
  const formik = useFormik({
    initialValues: { step1: '', step2: '' },
    onSubmit: (values) => console.log(values),
  });

  return (
    <FormikProvider value={formik}>
      <Form>
        <StepOne />
        <StepTwo />
        <button type="submit">Submit</button>
      </Form>
    </FormikProvider>
  );
}
```

### Full useFormik Example

```typescript
import { useFormik } from 'formik';
import * as Yup from 'yup';

function SettingsForm() {
  const formik = useFormik<SettingsValues>({
    initialValues: { notifications: true, language: 'en', timezone: 'UTC' },
    validationSchema: Yup.object({
      language: Yup.string().required(),
      timezone: Yup.string().required(),
    }),
    onSubmit: async (values, { setSubmitting }) => {
      await saveSettings(values);
      setSubmitting(false);
    },
  });

  return (
    <form onSubmit={formik.handleSubmit}>
      <select {...formik.getFieldProps('language')}>
        <option value="en">English</option>
        <option value="es">Spanish</option>
      </select>
      {formik.touched.language && formik.errors.language && <div>{formik.errors.language}</div>}
      <button type="submit" disabled={formik.isSubmitting}>Save</button>
    </form>
  );
}
```

### Full MUI Contact Form

```typescript
import { Formik, Form } from 'formik';
import { TextField, Button, Stack } from '@mui/material';
import * as Yup from 'yup';

const contactSchema = Yup.object({
  name: Yup.string().required('Name is required'),
  email: Yup.string().email('Invalid email').required('Email is required'),
  message: Yup.string().min(10, 'Too short').required('Message is required'),
});

function ContactForm() {
  return (
    <Formik<ContactValues>
      initialValues={{ name: '', email: '', message: '' }}
      validationSchema={contactSchema}
      onSubmit={async (values, { setSubmitting, resetForm }) => {
        await sendContact(values);
        setSubmitting(false);
        resetForm();
      }}
    >
      {({ values, errors, touched, handleChange, handleBlur, handleSubmit, isSubmitting }) => (
        <form onSubmit={handleSubmit}>
          <Stack spacing={2}>
            <TextField name="name" label="Name" value={values.name} onChange={handleChange} onBlur={handleBlur}
              error={touched.name && !!errors.name} helperText={touched.name && errors.name} fullWidth />
            <TextField name="email" label="Email" type="email" value={values.email} onChange={handleChange} onBlur={handleBlur}
              error={touched.email && !!errors.email} helperText={touched.email && errors.email} fullWidth />
            <TextField name="message" label="Message" multiline rows={4} value={values.message} onChange={handleChange} onBlur={handleBlur}
              error={touched.message && !!errors.message} helperText={touched.message && errors.message} fullWidth />
            <Button type="submit" variant="contained" disabled={isSubmitting}>Send</Button>
          </Stack>
        </form>
      )}
    </Formik>
  );
}
```
