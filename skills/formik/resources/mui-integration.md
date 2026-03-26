# MUI + Formik Integration

Patterns for wiring Formik form state to Material-UI components.

---

## TextField with Formik

### Using getFieldProps

```typescript
import { useFormik } from 'formik';
import { TextField, Button, Stack } from '@mui/material';
import * as Yup from 'yup';

interface FormValues {
  firstName: string;
  lastName: string;
  email: string;
}

function UserForm() {
  const formik = useFormik<FormValues>({
    initialValues: { firstName: '', lastName: '', email: '' },
    validationSchema: Yup.object({
      firstName: Yup.string().required('Required'),
      lastName: Yup.string().required('Required'),
      email: Yup.string().email('Invalid email').required('Required'),
    }),
    onSubmit: async (values) => {
      await saveUser(values);
    },
  });

  return (
    <form onSubmit={formik.handleSubmit}>
      <Stack spacing={2}>
        <TextField
          label="First Name"
          {...formik.getFieldProps('firstName')}
          error={formik.touched.firstName && !!formik.errors.firstName}
          helperText={formik.touched.firstName && formik.errors.firstName}
          fullWidth
        />
        <TextField
          label="Last Name"
          {...formik.getFieldProps('lastName')}
          error={formik.touched.lastName && !!formik.errors.lastName}
          helperText={formik.touched.lastName && formik.errors.lastName}
          fullWidth
        />
        <TextField
          label="Email"
          type="email"
          {...formik.getFieldProps('email')}
          error={formik.touched.email && !!formik.errors.email}
          helperText={formik.touched.email && formik.errors.email}
          fullWidth
        />
        <Button type="submit" variant="contained" disabled={formik.isSubmitting}>
          Save
        </Button>
      </Stack>
    </form>
  );
}
```

### Using Field with Custom Component

```typescript
import { Formik, Form, Field, FieldProps } from 'formik';
import { TextField } from '@mui/material';

function FormikMuiTextField({
  field,
  form: { touched, errors },
  ...props
}: FieldProps & React.ComponentProps<typeof TextField>) {
  const fieldError = touched[field.name] && errors[field.name];
  return (
    <TextField
      {...field}
      {...props}
      error={!!fieldError}
      helperText={fieldError as string}
      fullWidth
    />
  );
}

// Usage inside <Formik>
<Field name="email" component={FormikMuiTextField} label="Email" type="email" />
```

---

## Reusable FormikTextField Wrapper

A production-ready wrapper that handles nested field names and all MUI TextField props.

```typescript
import { useField } from 'formik';
import { TextField, type TextFieldProps } from '@mui/material';

type FormikTextFieldProps = {
  name: string;
} & Omit<TextFieldProps, 'name' | 'value' | 'onChange' | 'onBlur' | 'error' | 'helperText'>;

function FormikTextField({ name, ...props }: FormikTextFieldProps) {
  const [field, meta] = useField(name);
  const showError = meta.touched && !!meta.error;

  return (
    <TextField
      {...field}
      {...props}
      error={showError}
      helperText={showError ? meta.error : props.helperText}
      fullWidth={props.fullWidth ?? true}
    />
  );
}

export default FormikTextField;
```

Usage:

```typescript
import FormikTextField from './FormikTextField';

// Inside a <Formik> or <FormikProvider>
<FormikTextField name="email" label="Email" type="email" />
<FormikTextField name="address.street" label="Street" />
<FormikTextField name="bio" label="Bio" multiline rows={4} />
```

---

## Select with Formik

### Basic Select

```typescript
import { Formik, Form } from 'formik';
import {
  TextField,
  MenuItem,
  Button,
  Stack,
} from '@mui/material';

interface FormValues {
  country: string;
  role: string;
}

const countries = [
  { value: 'us', label: 'United States' },
  { value: 'uk', label: 'United Kingdom' },
  { value: 'de', label: 'Germany' },
  { value: 'jp', label: 'Japan' },
];

const roles = [
  { value: 'admin', label: 'Administrator' },
  { value: 'editor', label: 'Editor' },
  { value: 'viewer', label: 'Viewer' },
];

function SelectForm() {
  return (
    <Formik<FormValues>
      initialValues={{ country: '', role: '' }}
      onSubmit={(values) => console.log(values)}
    >
      {({ values, errors, touched, handleChange, handleBlur }) => (
        <Form>
          <Stack spacing={2}>
            <TextField
              select
              name="country"
              label="Country"
              value={values.country}
              onChange={handleChange}
              onBlur={handleBlur}
              error={touched.country && !!errors.country}
              helperText={touched.country && errors.country}
              fullWidth
            >
              {countries.map((option) => (
                <MenuItem key={option.value} value={option.value}>
                  {option.label}
                </MenuItem>
              ))}
            </TextField>

            <TextField
              select
              name="role"
              label="Role"
              value={values.role}
              onChange={handleChange}
              onBlur={handleBlur}
              error={touched.role && !!errors.role}
              helperText={touched.role && errors.role}
              fullWidth
            >
              {roles.map((option) => (
                <MenuItem key={option.value} value={option.value}>
                  {option.label}
                </MenuItem>
              ))}
            </TextField>

            <Button type="submit" variant="contained">Submit</Button>
          </Stack>
        </Form>
      )}
    </Formik>
  );
}
```

### Reusable FormikSelect

```typescript
import { useField } from 'formik';
import { TextField, MenuItem, type TextFieldProps } from '@mui/material';

interface SelectOption {
  value: string;
  label: string;
}

type FormikSelectProps = {
  name: string;
  options: SelectOption[];
} & Omit<TextFieldProps, 'name' | 'value' | 'onChange' | 'onBlur' | 'error' | 'helperText' | 'select'>;

function FormikSelect({ name, options, ...props }: FormikSelectProps) {
  const [field, meta] = useField(name);
  const showError = meta.touched && !!meta.error;

  return (
    <TextField
      select
      {...field}
      {...props}
      error={showError}
      helperText={showError ? meta.error : props.helperText}
      fullWidth={props.fullWidth ?? true}
    >
      {options.map((option) => (
        <MenuItem key={option.value} value={option.value}>
          {option.label}
        </MenuItem>
      ))}
    </TextField>
  );
}

export default FormikSelect;
```

---

## Checkbox with Formik

### Single Checkbox (Boolean)

```typescript
import { Formik, Form } from 'formik';
import { FormControlLabel, Checkbox, Button } from '@mui/material';

function TermsForm() {
  return (
    <Formik
      initialValues={{ acceptTerms: false, newsletter: false }}
      onSubmit={(values) => console.log(values)}
    >
      {({ values, handleChange, handleSubmit }) => (
        <form onSubmit={handleSubmit}>
          <FormControlLabel
            control={
              <Checkbox
                name="acceptTerms"
                checked={values.acceptTerms}
                onChange={handleChange}
              />
            }
            label="I accept the terms and conditions"
          />

          <FormControlLabel
            control={
              <Checkbox
                name="newsletter"
                checked={values.newsletter}
                onChange={handleChange}
              />
            }
            label="Subscribe to newsletter"
          />

          <Button type="submit" variant="contained">Submit</Button>
        </form>
      )}
    </Formik>
  );
}
```

### Checkbox Group (Array of Values)

```typescript
import { Formik, Form } from 'formik';
import {
  FormControl,
  FormLabel,
  FormGroup,
  FormControlLabel,
  FormHelperText,
  Checkbox,
} from '@mui/material';
import * as Yup from 'yup';

const interestOptions = ['Technology', 'Science', 'Art', 'Music', 'Sports'];

function InterestsForm() {
  return (
    <Formik
      initialValues={{ interests: [] as string[] }}
      validationSchema={Yup.object({
        interests: Yup.array()
          .of(Yup.string())
          .min(1, 'Select at least one interest'),
      })}
      onSubmit={(values) => console.log(values)}
    >
      {({ values, errors, touched, setFieldValue, handleSubmit }) => (
        <form onSubmit={handleSubmit}>
          <FormControl
            error={touched.interests && !!errors.interests}
            component="fieldset"
          >
            <FormLabel component="legend">Interests</FormLabel>
            <FormGroup>
              {interestOptions.map((interest) => (
                <FormControlLabel
                  key={interest}
                  control={
                    <Checkbox
                      checked={values.interests.includes(interest)}
                      onChange={(e) => {
                        const next = e.target.checked
                          ? [...values.interests, interest]
                          : values.interests.filter((i) => i !== interest);
                        setFieldValue('interests', next);
                      }}
                    />
                  }
                  label={interest}
                />
              ))}
            </FormGroup>
            {touched.interests && errors.interests && (
              <FormHelperText>{errors.interests}</FormHelperText>
            )}
          </FormControl>
        </form>
      )}
    </Formik>
  );
}
```

---

## Autocomplete with Formik

```typescript
import { Formik, Form } from 'formik';
import { Autocomplete, TextField, Button, Stack } from '@mui/material';
import * as Yup from 'yup';

interface TagOption {
  id: string;
  label: string;
}

const tagOptions: TagOption[] = [
  { id: '1', label: 'React' },
  { id: '2', label: 'TypeScript' },
  { id: '3', label: 'Node.js' },
  { id: '4', label: 'GraphQL' },
  { id: '5', label: 'Docker' },
];

interface FormValues {
  category: TagOption | null;
  tags: TagOption[];
}

function AutocompleteForm() {
  return (
    <Formik<FormValues>
      initialValues={{ category: null, tags: [] }}
      validationSchema={Yup.object({
        category: Yup.object().nullable().required('Category is required'),
        tags: Yup.array().min(1, 'Select at least one tag'),
      })}
      onSubmit={(values) => console.log(values)}
    >
      {({ values, errors, touched, setFieldValue, setFieldTouched, handleSubmit }) => (
        <form onSubmit={handleSubmit}>
          <Stack spacing={2}>
            {/* Single-value Autocomplete */}
            <Autocomplete
              options={tagOptions}
              getOptionLabel={(option) => option.label}
              value={values.category}
              onChange={(_, newValue) => setFieldValue('category', newValue)}
              onBlur={() => setFieldTouched('category', true)}
              isOptionEqualToValue={(option, value) => option.id === value.id}
              renderInput={(params) => (
                <TextField
                  {...params}
                  label="Category"
                  error={touched.category && !!errors.category}
                  helperText={touched.category && (errors.category as string)}
                />
              )}
            />

            {/* Multi-value Autocomplete */}
            <Autocomplete
              multiple
              options={tagOptions}
              getOptionLabel={(option) => option.label}
              value={values.tags}
              onChange={(_, newValue) => setFieldValue('tags', newValue)}
              onBlur={() => setFieldTouched('tags', true)}
              isOptionEqualToValue={(option, value) => option.id === value.id}
              renderInput={(params) => (
                <TextField
                  {...params}
                  label="Tags"
                  error={touched.tags && !!errors.tags}
                  helperText={touched.tags && (errors.tags as string)}
                />
              )}
            />

            <Button type="submit" variant="contained">Submit</Button>
          </Stack>
        </form>
      )}
    </Formik>
  );
}
```

---

## FieldArray with MUI

### Dynamic List Items

```typescript
import { Formik, Form, FieldArray } from 'formik';
import {
  TextField,
  Button,
  IconButton,
  List,
  ListItem,
  ListItemText,
  Stack,
  Typography,
  Paper,
} from '@mui/material';
import { Add as AddIcon, Delete as DeleteIcon } from '@mui/icons-material';
import * as Yup from 'yup';

interface PhoneEntry {
  label: string;
  number: string;
}

interface ContactValues {
  name: string;
  phones: PhoneEntry[];
}

const contactSchema = Yup.object({
  name: Yup.string().required('Name is required'),
  phones: Yup.array()
    .of(
      Yup.object({
        label: Yup.string().required('Label is required'),
        number: Yup.string()
          .matches(/^\+?[\d\s-()]+$/, 'Invalid phone number')
          .required('Phone number is required'),
      }),
    )
    .min(1, 'At least one phone number is required'),
});

function ContactForm() {
  const initialValues: ContactValues = {
    name: '',
    phones: [{ label: 'Mobile', number: '' }],
  };

  return (
    <Formik<ContactValues>
      initialValues={initialValues}
      validationSchema={contactSchema}
      onSubmit={(values) => console.log(values)}
    >
      {({ values, errors, touched, handleChange, handleBlur, handleSubmit }) => (
        <form onSubmit={handleSubmit}>
          <Stack spacing={3}>
            <TextField
              name="name"
              label="Contact Name"
              value={values.name}
              onChange={handleChange}
              onBlur={handleBlur}
              error={touched.name && !!errors.name}
              helperText={touched.name && errors.name}
              fullWidth
            />

            <FieldArray name="phones">
              {({ push, remove }) => (
                <Paper variant="outlined" sx={{ p: 2 }}>
                  <Typography variant="subtitle1" sx={{ mb: 2 }}>
                    Phone Numbers
                  </Typography>

                  <List disablePadding>
                    {values.phones.map((phone, index) => {
                      const labelError =
                        touched.phones?.[index]?.label &&
                        (errors.phones as PhoneEntry[] | undefined)?.[index]?.label;
                      const numberError =
                        touched.phones?.[index]?.number &&
                        (errors.phones as PhoneEntry[] | undefined)?.[index]?.number;

                      return (
                        <ListItem key={index} disableGutters sx={{ gap: 1 }}>
                          <TextField
                            name={`phones.${index}.label`}
                            label="Label"
                            value={phone.label}
                            onChange={handleChange}
                            onBlur={handleBlur}
                            error={!!labelError}
                            helperText={labelError}
                            size="small"
                            sx={{ width: 150 }}
                          />
                          <TextField
                            name={`phones.${index}.number`}
                            label="Number"
                            value={phone.number}
                            onChange={handleChange}
                            onBlur={handleBlur}
                            error={!!numberError}
                            helperText={numberError}
                            size="small"
                            sx={{ flex: 1 }}
                          />
                          <IconButton
                            onClick={() => remove(index)}
                            disabled={values.phones.length <= 1}
                            color="error"
                            size="small"
                          >
                            <DeleteIcon />
                          </IconButton>
                        </ListItem>
                      );
                    })}
                  </List>

                  {/* Array-level error */}
                  {typeof errors.phones === 'string' && (
                    <Typography color="error" variant="caption">
                      {errors.phones}
                    </Typography>
                  )}

                  <Button
                    startIcon={<AddIcon />}
                    onClick={() => push({ label: '', number: '' })}
                    sx={{ mt: 1 }}
                  >
                    Add Phone
                  </Button>
                </Paper>
              )}
            </FieldArray>

            <Button type="submit" variant="contained">
              Save Contact
            </Button>
          </Stack>
        </form>
      )}
    </Formik>
  );
}
```

### Accessing FieldArray Errors Safely

When accessing errors for FieldArray items with MUI, cast the errors object because Formik types `errors.phones` as `string | string[] | FormikErrors<PhoneEntry>[]`:

```typescript
// Safe access pattern for item-level errors in FieldArray
const phonesErrors = errors.phones as PhoneEntry[] | undefined;
const labelError = touched.phones?.[index]?.label && phonesErrors?.[index]?.label;
const numberError = touched.phones?.[index]?.number && phonesErrors?.[index]?.number;

// Array-level error (e.g., "At least one phone number required")
{typeof errors.phones === 'string' && (
  <Typography color="error" variant="caption">{errors.phones}</Typography>
)}
```

---

## DatePicker Integration

```typescript
import { Formik, Form } from 'formik';
import { TextField, Button, Stack } from '@mui/material';
import { DatePicker } from '@mui/x-date-pickers/DatePicker';
import { LocalizationProvider } from '@mui/x-date-pickers/LocalizationProvider';
import { AdapterDayjs } from '@mui/x-date-pickers/AdapterDayjs';
import dayjs, { Dayjs } from 'dayjs';
import * as Yup from 'yup';

interface EventValues {
  title: string;
  startDate: Dayjs | null;
  endDate: Dayjs | null;
}

const eventSchema = Yup.object({
  title: Yup.string().required('Title is required'),
  startDate: Yup.mixed<Dayjs>()
    .required('Start date is required')
    .test('valid', 'Invalid date', (value) => value !== null && dayjs(value).isValid()),
  endDate: Yup.mixed<Dayjs>()
    .required('End date is required')
    .test('valid', 'Invalid date', (value) => value !== null && dayjs(value).isValid())
    .test('after-start', 'End must be after start', function (value) {
      const { startDate } = this.parent;
      if (!value || !startDate) return true;
      return dayjs(value).isAfter(dayjs(startDate));
    }),
});

function EventForm() {
  return (
    <LocalizationProvider dateAdapter={AdapterDayjs}>
      <Formik<EventValues>
        initialValues={{ title: '', startDate: null, endDate: null }}
        validationSchema={eventSchema}
        onSubmit={(values) => console.log(values)}
      >
        {({
          values,
          errors,
          touched,
          handleChange,
          handleBlur,
          setFieldValue,
          setFieldTouched,
          handleSubmit,
        }) => (
          <form onSubmit={handleSubmit}>
            <Stack spacing={2}>
              <TextField
                name="title"
                label="Event Title"
                value={values.title}
                onChange={handleChange}
                onBlur={handleBlur}
                error={touched.title && !!errors.title}
                helperText={touched.title && errors.title}
                fullWidth
              />

              <DatePicker
                label="Start Date"
                value={values.startDate}
                onChange={(value) => setFieldValue('startDate', value)}
                slotProps={{
                  textField: {
                    onBlur: () => setFieldTouched('startDate', true),
                    error: touched.startDate && !!errors.startDate,
                    helperText: touched.startDate && (errors.startDate as string),
                    fullWidth: true,
                  },
                }}
              />

              <DatePicker
                label="End Date"
                value={values.endDate}
                onChange={(value) => setFieldValue('endDate', value)}
                minDate={values.startDate ?? undefined}
                slotProps={{
                  textField: {
                    onBlur: () => setFieldTouched('endDate', true),
                    error: touched.endDate && !!errors.endDate,
                    helperText: touched.endDate && (errors.endDate as string),
                    fullWidth: true,
                  },
                }}
              />

              <Button type="submit" variant="contained">
                Create Event
              </Button>
            </Stack>
          </form>
        )}
      </Formik>
    </LocalizationProvider>
  );
}
```

---

## Form Layout with MUI Grid and Stack

### Grid Layout

```typescript
import { Formik, Form } from 'formik';
import { Grid, TextField, Button, Typography, Divider } from '@mui/material';
import * as Yup from 'yup';

interface AddressFormValues {
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
  street: string;
  apt: string;
  city: string;
  state: string;
  zip: string;
}

const addressSchema = Yup.object({
  firstName: Yup.string().required('Required'),
  lastName: Yup.string().required('Required'),
  email: Yup.string().email('Invalid email').required('Required'),
  phone: Yup.string().required('Required'),
  street: Yup.string().required('Required'),
  apt: Yup.string(),
  city: Yup.string().required('Required'),
  state: Yup.string().required('Required'),
  zip: Yup.string().matches(/^\d{5}$/, 'Invalid ZIP').required('Required'),
});

function AddressForm() {
  const initialValues: AddressFormValues = {
    firstName: '', lastName: '', email: '', phone: '',
    street: '', apt: '', city: '', state: '', zip: '',
  };

  return (
    <Formik<AddressFormValues>
      initialValues={initialValues}
      validationSchema={addressSchema}
      onSubmit={(values) => console.log(values)}
    >
      {({ values, errors, touched, handleChange, handleBlur, handleSubmit }) => {
        const fieldProps = (name: keyof AddressFormValues) => ({
          name,
          value: values[name],
          onChange: handleChange,
          onBlur: handleBlur,
          error: touched[name] && !!errors[name],
          helperText: touched[name] && errors[name],
          fullWidth: true as const,
        });

        return (
          <form onSubmit={handleSubmit}>
            <Typography variant="h6" sx={{ mb: 2 }}>
              Personal Information
            </Typography>
            <Grid container spacing={2}>
              <Grid item xs={12} sm={6}>
                <TextField label="First Name" {...fieldProps('firstName')} />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField label="Last Name" {...fieldProps('lastName')} />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField label="Email" type="email" {...fieldProps('email')} />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField label="Phone" {...fieldProps('phone')} />
              </Grid>
            </Grid>

            <Divider sx={{ my: 3 }} />

            <Typography variant="h6" sx={{ mb: 2 }}>
              Address
            </Typography>
            <Grid container spacing={2}>
              <Grid item xs={12} sm={8}>
                <TextField label="Street" {...fieldProps('street')} />
              </Grid>
              <Grid item xs={12} sm={4}>
                <TextField label="Apt/Suite" {...fieldProps('apt')} />
              </Grid>
              <Grid item xs={12} sm={5}>
                <TextField label="City" {...fieldProps('city')} />
              </Grid>
              <Grid item xs={12} sm={4}>
                <TextField label="State" {...fieldProps('state')} />
              </Grid>
              <Grid item xs={12} sm={3}>
                <TextField label="ZIP" {...fieldProps('zip')} />
              </Grid>
            </Grid>

            <Button type="submit" variant="contained" sx={{ mt: 3 }}>
              Save Address
            </Button>
          </form>
        );
      }}
    </Formik>
  );
}
```

### Stack Layout (Simple Forms)

```typescript
import { Formik, Form } from 'formik';
import { Stack, TextField, Button } from '@mui/material';

function SimpleForm() {
  return (
    <Formik
      initialValues={{ name: '', email: '', message: '' }}
      onSubmit={(values) => console.log(values)}
    >
      {({ values, handleChange, handleBlur, handleSubmit }) => (
        <form onSubmit={handleSubmit}>
          <Stack spacing={2} sx={{ maxWidth: 500 }}>
            <TextField
              name="name"
              label="Name"
              value={values.name}
              onChange={handleChange}
              onBlur={handleBlur}
              fullWidth
            />
            <TextField
              name="email"
              label="Email"
              type="email"
              value={values.email}
              onChange={handleChange}
              onBlur={handleBlur}
              fullWidth
            />
            <TextField
              name="message"
              label="Message"
              multiline
              rows={4}
              value={values.message}
              onChange={handleChange}
              onBlur={handleBlur}
              fullWidth
            />
            <Button type="submit" variant="contained">
              Send
            </Button>
          </Stack>
        </form>
      )}
    </Formik>
  );
}
```

---

## Helper: fieldProps Factory

When wiring many MUI fields, reduce boilerplate with a helper:

```typescript
import { FormikProps } from 'formik';

function createFieldProps<T extends Record<string, unknown>>(formik: FormikProps<T>) {
  return (name: keyof T & string) => ({
    name,
    value: formik.values[name],
    onChange: formik.handleChange,
    onBlur: formik.handleBlur,
    error: formik.touched[name] && !!formik.errors[name],
    helperText: (formik.touched[name] && formik.errors[name]) as string | undefined,
    fullWidth: true as const,
  });
}

// Usage
function MyForm() {
  return (
    <Formik initialValues={{ a: '', b: '', c: '' }} onSubmit={handleSubmit}>
      {(formik) => {
        const fp = createFieldProps(formik);
        return (
          <form onSubmit={formik.handleSubmit}>
            <TextField label="A" {...fp('a')} />
            <TextField label="B" {...fp('b')} />
            <TextField label="C" {...fp('c')} />
          </form>
        );
      }}
    </Formik>
  );
}
```

---
