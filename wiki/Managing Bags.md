For those who want to take more control of your bag:

1. Open Addon Settings Page

   You will need to open the add-on settings page in the game, if you want to customize your categories. You have two ways:

   * type `/ac` in chat then press 'enter', or
   * press 'ESC', then select Settings -> Addons -> Auto Category

Looks like:



2. Rearrange your categories in your bag (Bag Settings)

   First, select a bag you want to modify.

   You must notice the headers added into your inventory already (If not, enable this add-on first.). Each header's name appears in the 'Categories' combo box. And you'll find its priority value to the right of the name. Higher priority means the position is more important and will get tested sooner.



   Select a category then drag the 'Run Priority' slider to a new value, then the execution order of this category will be changed immediately.
   Drag the 'Display Priority' slider to a new value, then the order that this category will be displayed in will change immediately.

   An item only belongs to ONE category at the same time, so if you want to move an item to another category, you have to make its category's run priority higher than its current one.

   Matching items will obey the run priority, if an item is matched by 'BoE' and 'Set(xxx)', it will show in the highest run priority one, not all of them
   
   With the Hide Category On/Off, you can specify that that category should match as specified by the run priority but that for this bag you do not want to see the items that matched. The category name will be greyed out in your inventory to signal that Hide Category was turned on. To see the items again, simply turn Hide Category OFF.

3. Add/Remove a category in the bag

   You can find a 'Remove' button under the 'Display Priority' slider. If you click it, current selected category will be removed from the bag shown in the left. Don't worry, this category can still be used later.

   If you want to add a new category for this bag, look at the 'Add Category' section. You will need to do these steps:

   * Select a tag. (A tag is for grouping categories, one category can be put in only one tag)
   * Select a category from this tag.
   * Click 'Add' button under the 'Edit' button.
   * Then the category is moved to your bag. You will find it in the categories in bag settings.

   Bags can be customized separately.

   In version 4.6.22, you can also right-click an inventory category header
   and select **New Category**. Enter a unique name in the popup; blank names
   and names already used by another category are refused, including names
   differing only in letter case. Cancel leaves the categories unchanged.

   The new category is added only to the clicked bag, at Normal level with
   no parent and the rule `false`. It automatically receives the highest
   display priority, without opening the category display order window.
   If priority 1000 is already occupied, existing display-priority groups
   are compacted below it without changing their relative order or ties.
   Execution priorities and other bags are unchanged. If all 999 distinct
   priorities from 2 through 1000 are occupied, creation is refused without
   changing existing categories. A `false` rule
   initially matches no items, so it does not create an empty header in the
   inventory item list. Assign items or nest matching categories under it
   when you want it to contain inventory entries.

4. Customize a category

   You can change a category's name, description, tag or even its rule to make better use of them. You can find examples of custom rules on the [Creating Custom Categories](https://github.com/Shadowfen/AutoCategory/wiki/Creating-Custom-Categories) page.



   Click 'Learn Rules' or just go to the [Rule Functions Reference](https://github.com/Shadowfen/AutoCategory/wiki/Rule-Function-Reference) page to learn all of the available rules. You can request more if you want more conditions to filter items.

5. Ooooops I screwed it up!

   Just click 'X' to reset and confirm. Everything is fine now.

--------------------------------------------------------------


_**Acknowledgement: Page is based on the older version by Rockingdice**_
