package com.selkorin.client

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView

class KeyAdapter(
    private var items: List<Vault.KeyMeta>,
    private var activeId: String?,
    private val onClick: (Vault.KeyMeta) -> Unit,
    private val onMenu: (Vault.KeyMeta) -> Unit,
) : RecyclerView.Adapter<KeyAdapter.VH>() {

    class VH(view: android.view.View) : RecyclerView.ViewHolder(view) {
        val dot: android.view.View = view.findViewById(R.id.keyDot)
        val name: android.widget.TextView = view.findViewById(R.id.keyName)
        val type: android.widget.TextView = view.findViewById(R.id.keyType)
        val badge: android.widget.TextView = view.findViewById(R.id.keyBadge)
        val menu: android.widget.TextView = view.findViewById(R.id.keyMenu)
    }

    fun update(newItems: List<Vault.KeyMeta>, newActiveId: String?) {
        items = newItems
        activeId = newActiveId
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val v = LayoutInflater.from(parent.context).inflate(R.layout.item_key, parent, false)
        return VH(v)
    }

    override fun getItemCount(): Int = items.size

    override fun onBindViewHolder(holder: VH, position: Int) {
        val item = items[position]
        val active = item.id == activeId
        holder.name.text = item.name
        holder.type.text = if (item.type == "vless") "VLESS · Reality" else "WireGuard"
        holder.badge.text = if (item.type == "vless") "VLESS" else "WG"
        holder.dot.setBackgroundResource(if (active) R.drawable.bg_power_on else R.drawable.bg_power_off)
        holder.itemView.setBackgroundResource(if (active) R.drawable.bg_card_active else R.drawable.bg_card)
        holder.itemView.setOnClickListener { onClick(item) }
        holder.menu.setOnClickListener { onMenu(item) }
    }
}
