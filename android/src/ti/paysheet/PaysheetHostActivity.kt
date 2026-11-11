/**
 * Ti.Paysheet — Stripe PaymentSheet and CustomerSheet for Titanium.
 * Copyright (c) 2026 Centreville Tech LLC. Licensed under the Apache License, Version 2.0.
 */
package ti.paysheet

import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import com.stripe.android.PaymentConfiguration
import com.stripe.android.core.exception.StripeException
import com.stripe.android.customersheet.CustomerSheet
import com.stripe.android.customersheet.CustomerSheetResult
import com.stripe.android.paymentsheet.PaymentSheet
import com.stripe.android.paymentsheet.PaymentSheetResult
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Invisible activity that owns one PaymentSheet or CustomerSheet presentation.
 *
 * Stripe registers its activity-result launchers when the sheet object is built, which must happen in onCreate().
 * Building it here (rather than in the Titanium window's activity) means the sheet is rebuilt and re-registered
 * whenever this activity is recreated, so a result still arrives after rotation or after the process was killed
 * while the customer was in a browser for 3-D Secure.
 */
class PaysheetHostActivity : ComponentActivity() {

	companion object {
		const val EXTRA_ID = "ti.paysheet.id"
		const val EXTRA_SHEET = "ti.paysheet.sheet"
		private const val STATE_PRESENTED = "presented"
		private const val STATE_DELIVERED = "delivered"
		private const val SETUP_INTENT_TIMEOUT_MS = 60_000L
	}

	private lateinit var requestId: String
	private lateinit var sheet: Options.Sheet
	private var paymentSheet: PaymentSheet? = null
	private var customerSheet: CustomerSheet? = null
	private var presented = false
	private var delivered = false

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		@Suppress("DEPRECATION")
		overridePendingTransition(0, 0)

		val id = intent.getStringExtra(EXTRA_ID)
		val parsed = if (Build.VERSION.SDK_INT >= 33) {
			intent.getSerializableExtra(EXTRA_SHEET, Options.Sheet::class.java)
		} else {
			@Suppress("DEPRECATION")
			intent.getSerializableExtra(EXTRA_SHEET) as? Options.Sheet
		}
		if (id == null || parsed == null) {
			Log.e(PaysheetModule.TAG, "host activity started without a sheet")
			finishQuietly()
			return
		}
		requestId = id
		sheet = parsed
		presented = savedInstanceState?.getBoolean(STATE_PRESENTED) ?: false
		delivered = savedInstanceState?.getBoolean(STATE_DELIVERED) ?: false
		if (delivered) {
			finishQuietly()
			return
		}
		if (savedInstanceState != null && !PaysheetModule.isLive(requestId)) {
			// Recreated in a new process (it was killed while the sheet, or a browser or bank app on top of it,
			// was open). Titanium cannot restore its own windows without their script: it closes them and
			// restarts the app, and the restarted app's window would open on top of the still-running sheet.
			// Turning this activity opaque stops Android recreating the Titanium window underneath until the
			// sheet has finished; the result is then kept for takeRestoredResult().
			becomeOpaque()
		}

		// Normally already done by initialize(); repeated here because after a process restart nothing else ran.
		PaymentConfiguration.init(applicationContext, sheet.publishableKey, sheet.stripeAccountId)

		try {
			if (sheet.mode == "customer") {
				val cs = CustomerSheet.create(this, SessionProvider(), ::onCustomerSheetResult)
				cs.configure(StripeConfig.customerSheetConfiguration(this, sheet))
				customerSheet = cs
			} else {
				paymentSheet = PaymentSheet.Builder(::onPaymentSheetResult).build(this)
			}
		} catch (e: Exception) {
			Log.e(PaysheetModule.TAG, "could not create the sheet", e)
			deliver(Results.failed(intentId(), null, Results.SDK_ERROR, e.message, null, null))
			return
		}

		if (!presented) {
			presented = true
			try {
				present()
			} catch (e: Exception) {
				Log.e(PaysheetModule.TAG, "could not present the sheet", e)
				deliver(Results.failed(intentId(), null, Results.SDK_ERROR, e.message, null, null))
			}
		}
	}

	private fun present() {
		customerSheet?.let {
			it.present()
			return
		}
		val ps = paymentSheet ?: return
		val configuration = StripeConfig.paymentSheetConfiguration(this, sheet)
		if (sheet.mode == "payment") {
			ps.presentWithPaymentIntent(sheet.intentClientSecret, configuration)
		} else {
			ps.presentWithSetupIntent(sheet.intentClientSecret, configuration)
		}
	}

	override fun onSaveInstanceState(outState: Bundle) {
		super.onSaveInstanceState(outState)
		outState.putBoolean(STATE_PRESENTED, presented)
		outState.putBoolean(STATE_DELIVERED, delivered)
	}

	override fun onDestroy() {
		// Finished without a result (should not happen; Stripe always reports one): never leave the caller hanging.
		if (isFinishing && !delivered && this::requestId.isInitialized) {
			delivered = true
			PaysheetModule.deliver(
				requestId,
				Results.moduleError(intentId(), Results.INTERRUPTED, "The payment sheet was closed by the system."),
			)
		}
		super.onDestroy()
	}

	private fun onPaymentSheetResult(result: PaymentSheetResult) {
		deliver(
			when (result) {
				is PaymentSheetResult.Completed -> Results.status(Results.COMPLETED, intentId())
				is PaymentSheetResult.Canceled -> Results.status(Results.CANCELED, intentId())
				is PaymentSheetResult.Failed -> failure(result.error)
			},
		)
	}

	private fun onCustomerSheetResult(result: CustomerSheetResult) {
		deliver(
			when (result) {
				is CustomerSheetResult.Selected ->
					Results.customer(Results.SELECTED, optionId(result.selection), result.selection?.paymentOption?.label)
				is CustomerSheetResult.Canceled ->
					Results.customer(Results.CANCELED, optionId(result.selection), result.selection?.paymentOption?.label)
				is CustomerSheetResult.Failed -> failure(result.exception)
			},
		)
	}

	private fun optionId(selection: com.stripe.android.customersheet.PaymentOptionSelection?): String? = when (selection) {
		is com.stripe.android.customersheet.PaymentOptionSelection.PaymentMethod -> selection.paymentMethod.id
		is com.stripe.android.customersheet.PaymentOptionSelection.GooglePay -> "google_pay"
		null -> null
	}

	private fun failure(error: Throwable): HashMap<String, Any?> {
		Log.w(PaysheetModule.TAG, "sheet failed: ${error.javaClass.simpleName}: ${error.message}")
		val stripeError = (error as? StripeException)?.stripeError
		// Stripe's loading exceptions are internal classes: their name (unless R8 renamed it) and their message are
		// the only handle on them.
		val terminal = error.javaClass.simpleName.let {
			it == "PaymentIntentInTerminalState" || it == "SetupIntentInTerminalState"
		} || Regex("cannot set up a (PaymentIntent|SetupIntent) in status").containsMatchIn(error.message ?: "")
		return Results.failed(
			intentId(),
			stripeError?.code ?: stripeError?.type,
			if (terminal) Results.INTENT_IN_TERMINAL_STATE else Results.SDK_ERROR,
			stripeError?.message ?: error.localizedMessage,
			stripeError?.declineCode,
			stripeError?.type,
		)
	}

	private fun intentId(): String? =
		if (this::sheet.isInitialized) Options.intentIdFromClientSecret(sheet.intentClientSecret) else null

	private fun deliver(result: HashMap<String, Any?>) {
		if (delivered) {
			return
		}
		delivered = true
		PaysheetModule.deliver(requestId, result)
		finishQuietly()
	}

	private fun becomeOpaque() {
		window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(0xFF202124.toInt()))
		if (Build.VERSION.SDK_INT >= 30) {
			setTranslucent(false)
		} else {
			Log.w(PaysheetModule.TAG, "restored after process death on Android < 11: the restarted app may cover the sheet")
		}
	}

	private fun finishQuietly() {
		finish()
		@Suppress("DEPRECATION")
		overridePendingTransition(0, 0)
	}

	/** Supplies CustomerSheet with the session given at presentation, and asks JavaScript for SetupIntents. */
	private inner class SessionProvider : CustomerSheet.CustomerSessionProvider() {
		override suspend fun providesCustomerSessionClientSecret(): Result<CustomerSheet.CustomerSessionClientSecret> =
			Result.success(
				CustomerSheet.CustomerSessionClientSecret.create(sheet.customerId, sheet.customerSessionClientSecret),
			)

		override suspend fun provideSetupIntentClientSecret(customerId: String): Result<String> {
			val answer = CompletableDeferred<Pair<String?, String?>>()
			PaysheetModule.requestSetupIntentSecret(requestId) { secret, error -> answer.complete(secret to error) }
			val (secret, error) = withTimeoutOrNull(SETUP_INTENT_TIMEOUT_MS) { answer.await() }
				?: (null to "fetchSetupIntentClientSecret did not answer within 60 seconds")
			return if (secret != null) Result.success(secret) else Result.failure(IllegalStateException(error))
		}
	}
}
