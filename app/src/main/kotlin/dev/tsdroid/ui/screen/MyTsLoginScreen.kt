package dev.tsdroid.ui.screen

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.tsdroid.R
import dev.tsdroid.data.MyTsSession
import dev.tsdroid.viewmodel.MyTsFailure
import dev.tsdroid.viewmodel.MyTsUiState
import dev.tsdroid.viewmodel.MyTsViewModel

/** The `myts_login` destination: wires [MyTsViewModel] to [MyTsLoginScreen]. */
@Composable
fun MyTsLoginRoute(
    onBack: () -> Unit,
    viewModel: MyTsViewModel = viewModel(),
) {
    val state by viewModel.state.collectAsState()
    MyTsLoginScreen(
        state = state,
        onBack = onBack,
        onLogin = viewModel::login,
        onLogout = viewModel::logout,
        onEmailChanged = { if (state.otpRequired) viewModel.resetOtp() else viewModel.clearFailure() },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyTsLoginScreen(
    state: MyTsUiState,
    onBack: () -> Unit,
    onLogin: (email: String, password: String, otp: String?) -> Unit,
    onLogout: () -> Unit,
    onEmailChanged: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.myts_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.myts_back),
                        )
                    }
                },
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            val session = state.session
            when {
                state.loading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                session != null -> LoggedIn(session, state.busy, onLogout)
                else -> LoginForm(state, onLogin, onEmailChanged)
            }
        }
    }
}

@Composable
private fun LoggedIn(session: MyTsSession, busy: Boolean, onLogout: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            stringResource(R.string.myts_logged_in_as, session.username.ifEmpty { session.email }),
            style = MaterialTheme.typography.titleMedium,
        )
        if (session.username.isNotEmpty() && session.email.isNotEmpty()) {
            Text(
                session.email,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(
            stringResource(R.string.myts_import_later),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedButton(onClick = onLogout, enabled = !busy) {
            Text(stringResource(R.string.myts_logout))
        }
    }
}

@Composable
private fun LoginForm(
    state: MyTsUiState,
    onLogin: (email: String, password: String, otp: String?) -> Unit,
    onEmailChanged: () -> Unit,
) {
    var email by rememberSaveable { mutableStateOf("") }
    // Plain remember: the password must not land in the saved-state Bundle.
    var password by remember { mutableStateOf("") }
    var otp by remember { mutableStateOf("") }
    var missingFields by remember { mutableStateOf(false) }

    val submit = {
        missingFields = email.isBlank() || password.isEmpty()
        if (!missingFields) onLogin(email, password, otp.takeIf { state.otpRequired && it.isNotBlank() })
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            stringResource(R.string.myts_login_intro),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 8.dp),
        )
        OutlinedTextField(
            value = email,
            onValueChange = { email = it; onEmailChanged() },
            label = { Text(stringResource(R.string.myts_email)) },
            singleLine = true,
            enabled = !state.busy,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text(stringResource(R.string.myts_password)) },
            singleLine = true,
            enabled = !state.busy,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
            modifier = Modifier.fillMaxWidth(),
        )
        if (state.otpRequired) {
            OutlinedTextField(
                value = otp,
                onValueChange = { otp = it.filter(Char::isDigit) },
                label = { Text(stringResource(R.string.myts_otp)) },
                singleLine = true,
                enabled = !state.busy,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        val message = when {
            missingFields -> stringResource(R.string.myts_error_fields_required)
            state.failure != null -> failureMessage(state.failure)
            else -> null
        }
        if (message != null) {
            Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
        }

        Button(
            onClick = submit,
            enabled = !state.busy,
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (state.busy) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            } else {
                val retry = state.failure?.retryable == true
                Text(stringResource(if (retry) R.string.myts_retry else R.string.myts_login))
            }
        }
    }
}

@Composable
private fun failureMessage(failure: MyTsFailure): String = when (failure.kind) {
    MyTsFailure.Kind.WRONG_CREDENTIALS -> stringResource(R.string.myts_error_wrong_credentials)
    MyTsFailure.Kind.EMAIL_PENDING -> stringResource(R.string.myts_error_email_pending)
    MyTsFailure.Kind.OTP_REQUIRED -> stringResource(R.string.myts_error_otp_required)
    MyTsFailure.Kind.OTP_INVALID -> stringResource(R.string.myts_error_otp_invalid)
    MyTsFailure.Kind.OTP_UNAVAILABLE -> stringResource(R.string.myts_error_otp_unavailable, failure.code)
    MyTsFailure.Kind.SERVICE_UNAVAILABLE -> stringResource(R.string.myts_error_service_unavailable)
    MyTsFailure.Kind.REJECTED -> stringResource(R.string.myts_error_rejected)
    MyTsFailure.Kind.TRANSIENT -> stringResource(R.string.myts_error_transient, failure.code)
    MyTsFailure.Kind.NETWORK -> stringResource(R.string.myts_error_network)
    MyTsFailure.Kind.PROTOCOL -> stringResource(R.string.myts_error_protocol)
    MyTsFailure.Kind.UNKNOWN -> stringResource(R.string.myts_error_unknown, failure.code)
}
