# Optional Stripe SDK features (3D Secure via Cardinal Commerce, Google Pay
# push-provisioning) whose classes aren't bundled since this app doesn't use
# them. R8 only needs permission to ignore the missing references.
-dontwarn com.cardinalcommerce.dependencies.internal.minidev.asm.Accessor
-dontwarn com.cardinalcommerce.dependencies.internal.minidev.asm.BeansAccess
-dontwarn com.cardinalcommerce.dependencies.internal.minidev.asm.ConvertDate
-dontwarn com.cardinalcommerce.dependencies.internal.minidev.asm.FieldFilter
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivity$g
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Args
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Error
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningEphemeralKeyProvider
