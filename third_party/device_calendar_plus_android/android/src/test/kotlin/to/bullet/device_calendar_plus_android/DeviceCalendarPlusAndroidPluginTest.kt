package to.bullet.device_calendar_plus_android

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import org.mockito.Mockito

internal class DeviceCalendarPlusAndroidPluginTest {
    @Test
    fun slowProviderDoesNotBlockCallerAndOperationsStayOrdered() {
        val plugin = DeviceCalendarPlusAndroidPlugin()
        val worker = Executors.newSingleThreadExecutor()
        val service = Mockito.mock(CalendarService::class.java)
        val firstResult = Mockito.mock(MethodChannel.Result::class.java)
        val secondResult = Mockito.mock(MethodChannel.Result::class.java)
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val caller = Thread.currentThread()
        var providerThread: Thread? = null
        for ((name, value) in mapOf("calendarWorker" to worker, "calendarService" to service)) {
            plugin.javaClass.getDeclaredField(name).apply {
                isAccessible = true
                set(plugin, value)
            }
        }
        Mockito.`when`(service.listCalendars()).thenAnswer {
            providerThread = Thread.currentThread()
            entered.countDown()
            check(release.await(5, TimeUnit.SECONDS))
            // Kotlin Result is unboxed at the mocked JVM method boundary.
            emptyList<Map<String, Any>>()
        }
        Mockito.`when`(service.listSources()).thenAnswer {
            emptyList<Map<String, Any>>()
        }
        try {
            plugin.onMethodCall(MethodCall("listCalendars", null), firstResult)
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            assertNotEquals(caller, providerThread)
            plugin.onMethodCall(MethodCall("listSources", null), secondResult)
            Mockito.verifyNoInteractions(firstResult, secondResult)
            release.countDown()
            worker.shutdown()
            assertTrue(worker.awaitTermination(5, TimeUnit.SECONDS))
            val order = Mockito.inOrder(firstResult, secondResult)
            order.verify(firstResult).success(emptyList<Map<String, Any>>())
            order.verify(secondResult).success(emptyList<Map<String, Any>>())
        } finally {
            release.countDown()
            worker.shutdownNow()
        }
    }

    @Test
    fun unknownMethodsReturnNotImplementedWithoutWorker() {
        val result = Mockito.mock(MethodChannel.Result::class.java)
        DeviceCalendarPlusAndroidPlugin().onMethodCall(MethodCall("unknown", null), result)
        Mockito.verify(result).notImplemented()
    }
}
