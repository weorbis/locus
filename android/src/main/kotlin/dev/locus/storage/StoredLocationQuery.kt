package dev.locus.storage

/** Private method-channel input; time edges use UTC epoch microseconds. */
internal data class StoredLocationQuery(
    val from: Long?,
    val to: Long?,
    val minAccuracy: Double?,
    val maxAccuracy: Double?,
    val isMoving: Boolean?,
    val bounds: Bounds?,
    val limit: Long?,
    val offset: Long,
    val oldestFirst: Boolean,
) {
    data class Bounds(
        val south: Double,
        val west: Double,
        val north: Double,
        val east: Double,
    ) {
        val hasNaN: Boolean
            get() = south.isNaN() || west.isNaN() || north.isNaN() || east.isNaN()
    }

    companion object {
        fun fromArguments(arguments: Any?): StoredLocationQuery {
            val map = arguments.asMapOrThrow("query")
            val bounds = map["bounds"]?.let { value ->
                val rectangle = value.asMapOrThrow("bounds")
                val southwest = rectangle["southwest"].asMapOrThrow("southwest")
                val northeast = rectangle["northeast"].asMapOrThrow("northeast")
                Bounds(
                    southwest.requiredDouble("latitude"),
                    southwest.requiredDouble("longitude"),
                    northeast.requiredDouble("latitude"),
                    northeast.requiredDouble("longitude"),
                )
            }
            val moving = map["isMoving"]?.let { value ->
                value as? Boolean ?: throw IllegalArgumentException("Expected isMoving boolean")
            }
            val oldestFirst = when (map["sortOrder"]) {
                null, "newestFirst" -> false
                "oldestFirst" -> true
                else -> throw IllegalArgumentException("Invalid sortOrder")
            }
            return StoredLocationQuery(
                from = map.optionalLong("from"),
                to = map.optionalLong("to"),
                minAccuracy = map.optionalDouble("minAccuracy"),
                maxAccuracy = map.optionalDouble("maxAccuracy"),
                isMoving = moving,
                bounds = bounds,
                limit = map.optionalLong("limit"),
                offset = (map.optionalLong("offset") ?: 0L).coerceAtLeast(0L),
                oldestFirst = oldestFirst,
            )
        }

        private fun Any?.asMapOrThrow(name: String): Map<*, *> =
            this as? Map<*, *> ?: throw IllegalArgumentException("Expected $name map")

        private fun Map<*, *>.optionalLong(key: String): Long? = when (val value = this[key]) {
            null -> null
            is Int -> value.toLong()
            is Long -> value
            else -> throw IllegalArgumentException("Expected integral $key")
        }

        private fun Map<*, *>.optionalDouble(key: String): Double? = when (val value = this[key]) {
            null -> null
            is Number -> value.toDouble()
            else -> throw IllegalArgumentException("Expected numeric $key")
        }

        private fun Map<*, *>.requiredDouble(key: String): Double =
            optionalDouble(key) ?: throw IllegalArgumentException("Missing numeric $key")
    }
}
